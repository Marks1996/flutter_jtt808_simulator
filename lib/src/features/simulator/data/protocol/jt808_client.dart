import 'dart:async';
import 'dart:io';

import '../../domain/simulator_models.dart';
import 'jt808_binary.dart';
import 'jt808_codec.dart';
import 'jt808_messages.dart';

/// A single 2013 terminal. Network failures are reported through [events], never
/// as uncaught stream errors. Invalid caller input can throw FormatException or
/// StateError. A successful [connect] starts, but does not await, authentication.
class Jt808Client {
  Jt808Client({
    required TerminalConfig config,
    LocationFix initialLocation = const LocationFix(),
    this._locationProvider,
    this.connectTimeout = const Duration(seconds: 10),
    this.responseTimeout = const Duration(seconds: 10),
    this.reconnectDelay = const Duration(seconds: 3),
    int initialSequence = 0,
  }) : _config = config,
       _location = initialLocation,
       _nextSequence = initialSequence {
    if (connectTimeout <= Duration.zero ||
        responseTimeout <= Duration.zero ||
        reconnectDelay <= Duration.zero) {
      throw ArgumentError('Timeouts and reconnect delay must be positive');
    }
    if (initialSequence < 0 || initialSequence > 0xffff) {
      throw ArgumentError.value(initialSequence, 'initialSequence');
    }
    _framer = Jt808PacketFramer(
      onError: (error, bytes) {
        _log(
          error.message,
          direction: LogDirection.received,
          bytes: bytes,
          error: true,
        );
      },
    );
    _parameters = {
      0x0001: (Jt808Writer()..dword(config.heartbeatSeconds)).toBytes(),
      0x0029: (Jt808Writer()..dword(config.locationIntervalSeconds)).toBytes(),
    };
  }

  TerminalConfig _config;
  TerminalConfig get config => _config;
  ConnectionPhase _phase = ConnectionPhase.disconnected;
  ConnectionPhase get phase => _phase;
  final Duration connectTimeout, responseTimeout, reconnectDelay;
  final _events = StreamController<ClientEvent>.broadcast();
  Stream<ClientEvent> get events => _events.stream;
  final _codec = const Jt808Codec();
  late final Jt808PacketFramer _framer;
  late Map<int, List<int>> _parameters;
  LocationFix _location;
  final LocationFix Function()? _locationProvider;
  Socket? _socket;
  ConnectionTask<Socket>? _connectionTask;
  StreamSubscription<List<int>>? _subscription;
  Timer? _handshakeTimer, _heartbeatTimer, _heartbeatTimeout;
  Timer? _locationTimer, _trackingExpiry, _reconnectTimer;
  int? _registrationSequence, _authenticationSequence, _heartbeatSequence;
  int? _trackingInterval;
  DateTime? _trackingDeadline;
  int _nextSequence;
  int _epoch = 0;
  bool _connecting = false, _desiredConnection = false, _disposed = false;
  Future<void> _writeTail = Future<void>.value();
  Future<void> _incomingTail = Future<void>.value();

  Future<void> connect() async {
    _checkAlive();
    if (_connecting || _socket != null) {
      throw StateError('Terminal is already connecting or connected');
    }
    if (_config.validationKey != null) {
      throw FormatException(
        'Invalid terminal configuration: ${_config.validationKey}',
      );
    }
    // Fail caller input before opening a socket.
    Jt808MessageBodies.location(_location);
    if (_config.authCode.isEmpty) {
      Jt808MessageBodies.registration(_config);
    } else {
      Jt808MessageBodies.authentication(_config.authCode);
    }
    _desiredConnection = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || !_desiredConnection) return;
    final epoch = ++_epoch;
    _connecting = true;
    _setPhase(
      ConnectionPhase.connecting,
      'Connecting to ${_config.host}:${_config.port}',
    );
    try {
      // Attach to task.socket before cancellation: cancelling an unobserved
      // connection future otherwise leaks a SocketException into the caller's
      // zone. The outer timeout also observes and cleans up a late DNS result.
      final socket = await Socket.startConnect(_config.host, _config.port)
          .then((task) {
            final pendingSocket = task.socket.then<Socket?>((socket) {
              if (!_current(epoch)) {
                socket.destroy();
                return null;
              }
              return socket;
            });
            if (_current(epoch)) {
              _connectionTask = task;
            } else {
              task.cancel();
            }
            return pendingSocket;
          })
          .timeout(connectTimeout);
      if (!_current(epoch) || socket == null) return;
      _connectionTask = null;
      _socket = socket;
      _connecting = false;
      socket.setOption(SocketOption.tcpNoDelay, true);
      _subscription = socket.listen(
        (data) => _receive(data, epoch),
        onError: (Object error, StackTrace stack) =>
            _fail(epoch, 'TCP error: $error'),
        onDone: () => _fail(epoch, 'Remote TCP connection closed'),
        cancelOnError: true,
      );
      if (_config.authCode.isNotEmpty) {
        await _authenticate(epoch);
      } else {
        _setPhase(ConnectionPhase.registering, 'Sending terminal registration');
        final sequence = _allocateSequence();
        _registrationSequence = sequence;
        _armHandshakeTimeout(epoch, 'Registration response timed out');
        await _send(
          0x0100,
          Jt808MessageBodies.registration(_config),
          epoch,
          sequence: sequence,
        );
      }
    } catch (error) {
      _fail(epoch, 'TCP connection failed: $error');
    } finally {
      if (_current(epoch)) _connecting = false;
    }
  }

  /// Updates the location used by 0x8201 and automatic reports while offline too.
  void updateLocation(LocationFix fix) {
    _checkAlive();
    Jt808MessageBodies.location(fix);
    _location = fix;
  }

  /// Pulls route state immediately before scheduled reports and location queries.
  /// Provider failures retain the last valid fix without breaking the session.
  LocationFix _locationForReport() {
    final provider = _locationProvider;
    if (provider != null) {
      try {
        updateLocation(provider());
      } catch (error) {
        _log(
          'Location provider failed; retaining last valid fix: $error',
          error: true,
        );
      }
    }
    return _location;
  }

  Future<void> sendLocation(LocationFix fix) async {
    updateLocation(fix);
    _requireOnline();
    await _send(0x0200, Jt808MessageBodies.location(fix), _epoch);
  }

  Future<void> heartbeat() async {
    _requireOnline();
    await _sendHeartbeat(_epoch);
  }

  /// Sends one checksum-validated 2013 packet, retaining its supplied sequence.
  Future<void> sendRaw(String hex) async {
    _checkAlive();
    final bytes = Jt808Codec.parseHex(hex);
    final frame = _codec.decode(bytes);
    if (frame.phone != _config.phone) {
      throw const FormatException(
        'Raw packet phone does not match this terminal',
      );
    }
    _requireOnline();
    await _write(frame, bytes, _epoch);
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _disconnect();
  }

  void _disconnect() {
    _desiredConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    ++_epoch;
    _releaseSession();
    _setPhase(ConnectionPhase.disconnected, 'Disconnected by user');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disconnect();
    _disposed = true;
    await _events.close();
  }

  Future<void> _authenticate(int epoch) async {
    if (!_current(epoch)) return;
    _handshakeTimer?.cancel();
    _setPhase(
      ConnectionPhase.authenticating,
      'Sending terminal authentication',
    );
    final sequence = _allocateSequence();
    _authenticationSequence = sequence;
    _armHandshakeTimeout(epoch, 'Authentication response timed out');
    await _send(
      0x0102,
      Jt808MessageBodies.authentication(_config.authCode),
      epoch,
      sequence: sequence,
    );
  }

  void _receive(List<int> data, int epoch) {
    if (!_current(epoch)) return;
    // Apply TCP backpressure while handlers await writes, rather than allowing
    // an unbounded future/packet queue if a platform floods commands.
    _subscription?.pause();
    for (final bytes in _framer.add(data)) {
      Jt808Frame frame;
      try {
        frame = _codec.decode(bytes);
      } on FormatException catch (error) {
        _log(
          error.message,
          direction: LogDirection.received,
          bytes: bytes,
          error: true,
        );
        continue;
      }
      _log(
        'Received ${_id(frame.messageId)}',
        direction: LogDirection.received,
        frame: frame,
        bytes: bytes,
      );
      _incomingTail = _incomingTail.then((_) async {
        if (!_current(epoch)) return;
        if (frame.phone != _config.phone) {
          _log(
            'Ignoring packet addressed to ${frame.phone}',
            frame: frame,
            error: true,
          );
          return;
        }
        try {
          await _handle(frame, epoch);
        } on FormatException catch (error) {
          _log(
            'Invalid ${_id(frame.messageId)} body: ${error.message}',
            frame: frame,
            error: true,
          );
          if (frame.messageId == 0x8100 &&
              _phase == ConnectionPhase.registering) {
            _fail(epoch, 'Invalid registration response');
          } else if (frame.messageId != 0x8001 && frame.messageId != 0x8100) {
            await _respond(frame, 2, epoch);
          }
        } catch (error) {
          _fail(epoch, 'Failed to process platform message: $error');
        }
      });
    }
    unawaited(
      _incomingTail.then(
        (_) {
          if (_current(epoch)) _subscription?.resume();
        },
        onError: (Object error, StackTrace stack) {
          _fail(epoch, 'Incoming command queue failed: $error');
        },
      ),
    );
  }

  Future<void> _handle(Jt808Frame frame, int epoch) async {
    final reader = Jt808Reader(frame.body);
    if (frame.messageId == 0x8100) {
      final requestSequence = reader.word();
      final result = reader.byte();
      if (_phase != ConnectionPhase.registering ||
          requestSequence != _registrationSequence) {
        _log(
          'Ignored registration response with no matching request',
          frame: frame,
          error: true,
        );
        return;
      }
      if (result != 0) {
        _fail(epoch, 'Registration rejected (result $result)');
        return;
      }
      final code = Jt808MessageBodies.decodeGbk(reader.take(reader.remaining));
      Jt808MessageBodies.authentication(code);
      _registrationSequence = null;
      _config = _config.withAuthCode(code);
      _emit(AuthenticationCodeReceived(code));
      await _authenticate(epoch);
      return;
    }
    if (frame.messageId == 0x8001) {
      final requestSequence = reader.word();
      final requestId = reader.word();
      final result = reader.byte();
      reader.requireEnd();
      if (_phase == ConnectionPhase.authenticating &&
          requestId == 0x0102 &&
          requestSequence == _authenticationSequence) {
        if (result != 0) {
          _fail(epoch, 'Authentication rejected (result $result)');
        } else {
          _handshakeTimer?.cancel();
          _handshakeTimer = null;
          _authenticationSequence = null;
          _setPhase(ConnectionPhase.online, 'Terminal authenticated');
          _restartHeartbeatTimer(epoch);
          _restartLocationTimer(epoch);
        }
      } else if (requestId == 0x0002 && requestSequence == _heartbeatSequence) {
        _heartbeatTimeout?.cancel();
        _heartbeatTimeout = null;
        _heartbeatSequence = null;
        if (result != 0) _fail(epoch, 'Heartbeat rejected (result $result)');
      } else {
        _log(
          'Platform response: request ${_id(requestId)}/$requestSequence, result $result; '
          'no matching authentication or heartbeat',
          frame: frame,
          error: result != 0,
        );
      }
      return; // Never acknowledge a platform acknowledgement.
    }
    if (_phase != ConnectionPhase.online) {
      _log('Command received before authentication', frame: frame, error: true);
      if (frame.messageId >= 0x8000) await _respond(frame, 1, epoch);
      return;
    }
    switch (frame.messageId) {
      case 0x8201:
        reader.requireEnd();
        final body = Jt808Writer()
          ..word(frame.sequence)
          ..bytes(Jt808MessageBodies.location(_locationForReport()));
        await _send(0x0201, body.toBytes(), epoch);
      case 0x8103:
        await _setParameters(frame, reader, epoch);
      case 0x8104:
        reader.requireEnd();
        await _sendParameters(frame, _parameters.keys.toList(), epoch);
      case 0x8106:
        final count = reader.byte();
        final ids = [for (var i = 0; i < count; i++) reader.dword()];
        reader.requireEnd();
        await _sendParameters(frame, ids.toSet().toList(), epoch);
      case 0x8300:
        final flags = reader.byte();
        final text = Jt808MessageBodies.decodeGbk(
          reader.take(reader.remaining),
        );
        _log(
          'Platform text (flags 0x${flags.toRadixString(16)}): $text',
          frame: frame,
        );
        await _respond(frame, 0, epoch);
      case 0x8202:
        final interval = reader.word();
        final duration = reader.remaining == 0 && interval == 0
            ? 0
            : reader.dword();
        reader.requireEnd();
        if (interval > 0 && (duration == 0 || duration < interval)) {
          throw const FormatException(
            'Tracking duration must be at least its positive interval',
          );
        }
        _trackingExpiry?.cancel();
        _trackingExpiry = null;
        _trackingInterval = interval == 0 ? null : interval;
        _trackingDeadline = interval == 0
            ? null
            : DateTime.now().toUtc().add(Duration(seconds: duration));
        if (interval != 0) {
          _trackingExpiry = Timer(Duration(seconds: duration), () {
            if (_current(epoch)) _endTracking(epoch);
          });
        }
        _restartLocationTimer(epoch);
        _log(
          interval == 0
              ? 'Temporary tracking stopped'
              : 'Temporary tracking every ${interval}s for ${duration}s',
          frame: frame,
        );
        await _respond(frame, 0, epoch);
      default:
        _log(
          'Unsupported platform command ${_id(frame.messageId)}',
          frame: frame,
          error: true,
        );
        if (frame.messageId >= 0x8000) await _respond(frame, 3, epoch);
    }
  }

  Future<void> _setParameters(
    Jt808Frame frame,
    Jt808Reader reader,
    int epoch,
  ) async {
    final count = reader.byte();
    final updates = <int, List<int>>{};
    var unsupported = false;
    for (var i = 0; i < count; i++) {
      final id = reader.dword();
      final value = reader.take(reader.byte());
      if (updates.containsKey(id)) {
        throw const FormatException('Duplicate parameter ID');
      }
      updates[id] = value;
      if (!_parameters.containsKey(id)) {
        unsupported = true;
      } else {
        if (value.length != 4) {
          throw const FormatException('Supported parameter must be a DWORD');
        }
        final seconds = Jt808Reader(value).dword();
        // Deliberate simulator limit, consistent with TerminalConfig validation.
        if (seconds < 1 || seconds > 3600) {
          throw const FormatException(
            'Supported intervals must be in 1..3600 seconds',
          );
        }
      }
    }
    reader.requireEnd();
    if (unsupported) {
      _log(
        'Parameter update rejected atomically: supported IDs are 0x0001 and 0x0029',
        frame: frame,
        error: true,
      );
      await _respond(frame, 3, epoch);
      return;
    }
    final next = {..._parameters, ...updates};
    _config = TerminalConfig.fromJson({
      ..._config.toJson(),
      'heartbeatSeconds': Jt808Reader(next[0x0001]!).dword(),
      'locationIntervalSeconds': Jt808Reader(next[0x0029]!).dword(),
    });
    _parameters = next;
    _emit(
      ParametersChanged(
        Map.unmodifiable({
          for (final entry in next.entries)
            entry.key: List<int>.unmodifiable(entry.value),
        }),
      ),
    );
    _restartHeartbeatTimer(epoch);
    _restartLocationTimer(epoch);
    await _respond(frame, 0, epoch);
  }

  Future<void> _sendParameters(
    Jt808Frame frame,
    List<int> ids,
    int epoch,
  ) async {
    final supported = ids.where(_parameters.containsKey).toList();
    final body = Jt808Writer()
      ..word(frame.sequence)
      ..byte(supported.length);
    for (final id in supported) {
      final value = _parameters[id]!;
      body
        ..dword(id)
        ..byte(value.length)
        ..bytes(value);
    }
    if (supported.length != ids.length) {
      _log(
        'Parameter query returns only supported IDs (0x0001, 0x0029)',
        frame: frame,
      );
    }
    await _send(0x0104, body.toBytes(), epoch);
  }

  Future<void> _respond(Jt808Frame frame, int result, int epoch) => _send(
    0x0001,
    Jt808MessageBodies.generalResponse(frame.sequence, frame.messageId, result),
    epoch,
  );

  int _allocateSequence() {
    final result = _nextSequence;
    _nextSequence = (_nextSequence + 1) & 0xffff;
    return result;
  }

  Future<void> _send(int id, List<int> body, int epoch, {int? sequence}) {
    final frame = Jt808Frame(
      messageId: id,
      phone: _config.phone,
      sequence: sequence ?? _allocateSequence(),
      body: body,
    );
    return _write(frame, _codec.encode(frame), epoch);
  }

  Future<void> _write(Jt808Frame frame, List<int> bytes, int epoch) {
    final operation = _writeTail.then((_) async {
      if (!_current(epoch) || _socket == null) return;
      final socket = _socket!;
      try {
        socket.add(bytes);
        await socket.flush().timeout(responseTimeout);
        _log(
          'Sent ${_id(frame.messageId)}',
          direction: LogDirection.sent,
          frame: frame,
          bytes: bytes,
        );
      } catch (error) {
        _fail(epoch, 'TCP write failed: $error');
      }
    });
    _writeTail = operation;
    return operation;
  }

  Future<void> _sendHeartbeat(int epoch) async {
    if (!_current(epoch) ||
        _phase != ConnectionPhase.online ||
        _heartbeatSequence != null) {
      return;
    }
    final sequence = _allocateSequence();
    _heartbeatSequence = sequence;
    await _send(0x0002, const [], epoch, sequence: sequence);
    if (_current(epoch) && _heartbeatSequence == sequence) {
      _heartbeatTimeout = Timer(
        responseTimeout,
        () => _fail(epoch, 'Heartbeat response timed out'),
      );
    }
  }

  void _restartHeartbeatTimer(int epoch) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _config.heartbeatSeconds),
      (_) {
        if (_current(epoch) && _phase == ConnectionPhase.online) {
          _background(() => _sendHeartbeat(epoch), epoch);
        }
      },
    );
  }

  void _restartLocationTimer(int epoch) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      Duration(seconds: _trackingInterval ?? _config.locationIntervalSeconds),
      (_) {
        if (!_current(epoch) || _phase != ConnectionPhase.online) return;
        if (_trackingDeadline != null &&
            !DateTime.now().toUtc().isBefore(_trackingDeadline!)) {
          _endTracking(epoch);
          return;
        }
        _background(
          () => _send(
            0x0200,
            Jt808MessageBodies.location(_locationForReport()),
            epoch,
          ),
          epoch,
        );
      },
    );
  }

  void _endTracking(int epoch) {
    _trackingExpiry?.cancel();
    _trackingExpiry = null;
    _trackingInterval = null;
    _trackingDeadline = null;
    _restartLocationTimer(epoch);
    _log('Temporary tracking expired; normal reporting interval restored');
  }

  void _background(Future<void> Function() action, int epoch) {
    unawaited(
      Future<void>.sync(action).catchError((Object error) {
        _fail(epoch, 'Background protocol operation failed: $error');
      }),
    );
  }

  void _armHandshakeTimeout(int epoch, String message) {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(responseTimeout, () => _fail(epoch, message));
  }

  void _fail(int epoch, String reason) {
    if (!_current(epoch)) return;
    _log(reason, error: true);
    ++_epoch;
    _releaseSession();
    _setPhase(ConnectionPhase.failed, reason);
    if (_desiredConnection && _config.autoReconnect && !_disposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDelay, () {
        _reconnectTimer = null;
        _background(_connect, _epoch);
      });
    }
  }

  void _releaseSession() {
    for (final timer in [
      _handshakeTimer,
      _heartbeatTimer,
      _heartbeatTimeout,
      _locationTimer,
      _trackingExpiry,
    ]) {
      timer?.cancel();
    }
    _handshakeTimer = _heartbeatTimer = _heartbeatTimeout = null;
    _locationTimer = _trackingExpiry = null;
    _registrationSequence = _authenticationSequence = _heartbeatSequence = null;
    _trackingInterval = null;
    _trackingDeadline = null;
    _connecting = false;
    _connectionTask?.cancel();
    _connectionTask = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(
        subscription.cancel().catchError((Object error) {
          _log('TCP subscription cancellation failed: $error', error: true);
        }),
      );
    }
    _socket?.destroy();
    _socket = null;
    _framer.reset();
    // New sessions must not wait for an old socket's pending flush or handler.
    _writeTail = Future<void>.value();
    _incomingTail = Future<void>.value();
  }

  bool _current(int epoch) => !_disposed && _epoch == epoch;
  void _checkAlive() {
    if (_disposed) throw StateError('Terminal client has been disposed');
  }

  void _requireOnline() {
    _checkAlive();
    if (_phase != ConnectionPhase.online || _socket == null) {
      throw StateError('Terminal is not authenticated and online');
    }
  }

  void _emit(ClientEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _setPhase(ConnectionPhase phase, String details) {
    _phase = phase;
    _emit(ConnectionChanged(phase, details));
  }

  void _log(
    String message, {
    LogDirection direction = LogDirection.event,
    Jt808Frame? frame,
    List<int> bytes = const [],
    bool error = false,
  }) {
    _emit(
      LogEmitted(
        ProtocolLog(
          terminalId: _config.id,
          direction: direction,
          message: message,
          messageId: frame?.messageId,
          sequence: frame?.sequence,
          hex: Jt808Codec.toHex(bytes),
          isError: error,
        ),
      ),
    );
  }

  static String _id(int value) =>
      '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}
