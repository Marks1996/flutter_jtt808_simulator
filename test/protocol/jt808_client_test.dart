import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_binary.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_client.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_codec.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_messages.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_models.dart';

void main() {
  late _Platform platform;
  final clients = <Jt808Client>[];

  setUp(() async {
    platform = await _Platform.bind();
  });
  tearDown(() async {
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
    await platform.close();
  });

  Jt808Client create({
    String authCode = '',
    bool autoReconnect = false,
    Duration responseTimeout = const Duration(seconds: 2),
    int initialSequence = 0,
    int heartbeatSeconds = 3600,
    int locationIntervalSeconds = 3600,
    LocationFix Function()? locationProvider,
  }) {
    final client = Jt808Client(
      config: TerminalConfig(
        id: 'terminal-key',
        host: '127.0.0.1',
        port: platform.port,
        plate: '京A12345',
        authCode: authCode,
        heartbeatSeconds: heartbeatSeconds,
        locationIntervalSeconds: locationIntervalSeconds,
        autoReconnect: autoReconnect,
      ),
      locationProvider: locationProvider,
      responseTimeout: responseTimeout,
      reconnectDelay: const Duration(milliseconds: 80),
      initialSequence: initialSequence,
    );
    clients.add(client);
    return client;
  }

  test('location provider is pulled freshly for every 0x8201 query', () async {
    var calls = 0;
    var current = LocationFix(
      latitude: 1.25,
      longitude: -2.5,
      recordedAt: DateTime.utc(2026),
    );
    final client = create(
      authCode: 'saved',
      locationProvider: () {
        calls++;
        return current;
      },
    );
    final peer = await _online(platform, client);
    expect(calls, 0, reason: 'connecting does not advance route state');
    await peer.send(0x8201, const [], sequence: 41);
    final first = Jt808Reader((await peer.next(0x0201)).body);
    expect(first.word(), 41);
    expect(first.take(first.remaining), Jt808MessageBodies.location(current));
    current = current.copyWith(latitude: -3.75, longitude: 4.5);
    await peer.send(0x8201, const [], sequence: 42);
    final second = Jt808Reader((await peer.next(0x0201)).body);
    expect(second.word(), 42);
    expect(second.take(second.remaining), Jt808MessageBodies.location(current));
    expect(calls, 2);
    // Explicit manual reporting still uses its supplied fix, not the getter.
    final explicit = current.copyWith(latitude: 8.5);
    await client.sendLocation(explicit);
    expect(
      (await peer.next(0x0200)).body,
      Jt808MessageBodies.location(explicit),
    );
    expect(calls, 2);
  });

  test(
    'location provider feeds normal and temporary client-owned reports',
    () async {
      var calls = 0;
      var current = LocationFix(latitude: 5.25, recordedAt: DateTime.utc(2026));
      final client = create(
        authCode: 'saved',
        locationIntervalSeconds: 1,
        locationProvider: () {
          calls++;
          return current;
        },
      );
      final peer = await _online(platform, client);
      expect(
        (await peer.next(0x0200)).body,
        Jt808MessageBodies.location(current),
      );
      expect(calls, 1);
      await peer.send(0x8103, _parameters({0x29: _dword(3600)}));
      expect((await peer.next(0x0001)).body.last, 0);
      current = current.copyWith(latitude: -6.5, longitude: -7.75);
      await peer.send(0x8202, [0, 1, ..._dword(4)]);
      expect((await peer.next(0x0001)).body.last, 0);
      expect(
        (await peer.next(0x0200)).body,
        Jt808MessageBodies.location(current),
      );
      expect(calls, 2);
      await peer.send(0x8202, [0, 0]);
      expect((await peer.next(0x0001)).body.last, 0);
      expect(client.config.locationIntervalSeconds, 3600);
    },
  );

  test(
    'location provider failures are logged and retain the last valid fix',
    () async {
      var mode = 'throw';
      final valid = LocationFix(
        latitude: -8.25,
        recordedAt: DateTime.utc(2026),
      );
      final client = create(
        authCode: 'saved',
        locationIntervalSeconds: 1,
        locationProvider: () {
          if (mode == 'throw') {
            throw StateError('route unavailable');
          }
          if (mode == 'invalid') {
            return const LocationFix(latitude: 91);
          }
          return valid;
        },
      );
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final peer = await _online(platform, client);
      await peer.send(0x8201, const []);
      final fallbackQuery = Jt808Reader((await peer.next(0x0201)).body);
      fallbackQuery.word();
      fallbackQuery.dword();
      fallbackQuery.dword();
      expect(fallbackQuery.dword(), 39904200);
      final fallbackReport = Jt808Reader((await peer.next(0x0200)).body);
      fallbackReport.dword();
      fallbackReport.dword();
      expect(fallbackReport.dword(), 39904200);
      mode = 'valid';
      await peer.send(0x8201, const []);
      final recovered = Jt808Reader((await peer.next(0x0201)).body);
      recovered.word();
      expect(
        recovered.take(recovered.remaining),
        Jt808MessageBodies.location(valid),
      );
      mode = 'invalid';
      await peer.send(0x8201, const []);
      final retained = Jt808Reader((await peer.next(0x0201)).body);
      retained.word();
      expect(
        retained.take(retained.remaining),
        Jt808MessageBodies.location(valid),
      );
      await _settle();
      final failures = events
          .whereType<LogEmitted>()
          .map((e) => e.log)
          .where(
            (log) =>
                log.isError && log.message.contains('Location provider failed'),
          );
      expect(failures.length, greaterThanOrEqualTo(3));
      expect(
        failures.any((log) => log.message.contains('route unavailable')),
        isTrue,
      );
      expect(
        failures.any((log) => log.message.contains('invalid_coordinates')),
        isTrue,
      );
      expect(client.phase, ConnectionPhase.online);
    },
  );

  // Keep GBK fixtures with TCP cases: concurrent lazy initialization of the
  // dependency's huge generated maps in Flutter test isolates caused a
  // reproducible Map._fromLiteral type error with randomized suite order.
  test('2013 registration widths and real GBK Chinese plate', () {
    const config = TerminalConfig(
      id: 'test',
      province: 11,
      city: 101,
      manufacturer: 'ABC',
      model: 'SIM',
      terminalId: 'A1',
      plate: '京A12345',
    );
    final bytes = Jt808MessageBodies.registration(config);
    expect(bytes.sublist(0, 4), [0, 11, 0, 101]);
    expect(bytes.sublist(4, 9), [65, 66, 67, 0, 0]);
    expect(bytes.sublist(9, 29), [83, 73, 77, ...List.filled(17, 0)]);
    expect(bytes.sublist(29, 36), [65, 49, 0, 0, 0, 0, 0]);
    expect(bytes[36], 1);
    expect(bytes.sublist(37), [0xbe, 0xa9, 0x41, 0x31, 0x32, 0x33, 0x34, 0x35]);
    expect(Jt808MessageBodies.decodeGbk(bytes.sublist(37)), '京A12345');
    expect(Jt808MessageBodies.encodeGbk('中文'), [0xd6, 0xd0, 0xce, 0xc4]);
    expect(() => Jt808MessageBodies.encodeGbk('🚗'), throwsFormatException);
    // The dependency otherwise emits U+00FF as a single invalid 0xFF byte.
    expect(() => Jt808MessageBodies.encodeGbk('ÿ'), throwsFormatException);
    expect(() => Jt808MessageBodies.decodeGbk([0xff]), throwsFormatException);
    expect(() => Jt808MessageBodies.decodeGbk([0xd6]), throwsFormatException);
    expect(
      () => Jt808MessageBodies.decodeGbk([0x81, 0x7f]),
      throwsFormatException,
    );
  });

  test(
    'real TCP registration, correlated authentication, location query, heartbeat and logs',
    () async {
      final client = create();
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      client.updateLocation(
        LocationFix(
          latitude: -30.123456,
          longitude: 120.654321,
          recordedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await client.connect();
      expect(
        client.phase,
        ConnectionPhase.registering,
        reason: 'connect must return without waiting for authentication',
      );
      final peer = await platform.nextPeer();
      final registration = await peer.next(0x0100);
      expect(registration.body, Jt808MessageBodies.registration(client.config));
      expect(
        registration.body.sublist(37),
        Jt808MessageBodies.encodeGbk('京A12345'),
      );
      await peer.send(
        0x8100,
        (Jt808Writer()
              ..word(registration.sequence + 1)
              ..byte(1))
            .toBytes(),
      );
      await peer.send(
        0x8100,
        (Jt808Writer()
              ..word(registration.sequence + 1)
              ..byte(0)
              ..bytes(Jt808MessageBodies.encodeGbk('wrong')))
            .toBytes(),
      );
      await _settle();
      expect(client.phase, ConnectionPhase.registering);
      expect(peer.received.where((f) => f.messageId == 0x0102), isEmpty);
      expect(events.whereType<AuthenticationCodeReceived>(), isEmpty);

      const code = '密钥123';
      final response = const Jt808Codec().encode(
        Jt808Frame(
          messageId: 0x8100,
          phone: client.config.phone,
          sequence: 200,
          body:
              (Jt808Writer()
                    ..word(registration.sequence)
                    ..byte(0)
                    ..bytes(Jt808MessageBodies.encodeGbk(code)))
                  .toBytes(),
        ),
      );
      // A real TCP write split inside the registration response.
      await peer.write(response.sublist(0, 8));
      await peer.write(response.sublist(8));
      final authentication = await peer.next(0x0102);
      expect(authentication.body, Jt808MessageBodies.encodeGbk(code));
      expect(client.config.authCode, code);
      await peer.ack(authentication, requestId: 0x0002);
      await peer.ack(
        authentication,
        requestSequence: authentication.sequence + 1,
      );
      await _settle();
      expect(client.phase, ConnectionPhase.authenticating);
      await peer.ack(authentication);
      await _until(() => client.phase == ConnectionPhase.online);
      await _settle();
      expect(
        peer.received.where((f) => f.messageId == 0x0001),
        isEmpty,
        reason: '0x8001 must never itself be acknowledged',
      );

      await peer.send(0x8201, const [], sequence: 0x7e);
      final locationAnswer = await peer.next(0x0201);
      final reader = Jt808Reader(locationAnswer.body);
      expect(reader.word(), 0x7e);
      expect(
        reader.take(reader.remaining),
        Jt808MessageBodies.location(
          LocationFix(
            latitude: -30.123456,
            longitude: 120.654321,
            recordedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      );
      client.updateLocation(
        LocationFix(
          latitude: 10,
          longitude: -20,
          recordedAt: DateTime.utc(2026, 2, 2),
        ),
      );
      await peer.send(0x8201, const [], sequence: 400);
      final latest = Jt808Reader((await peer.next(0x0201)).body);
      expect(latest.word(), 400);
      latest.dword();
      expect(latest.dword() & 0x0c, 8);
      expect(latest.dword(), 10000000);
      expect(latest.dword(), 20000000);

      await client.heartbeat();
      final heartbeat = await peer.next(0x0002);
      expect(heartbeat.body, isEmpty);
      await peer.ack(heartbeat);
      await _settle();
      expect(events.whereType<AuthenticationCodeReceived>().single.code, code);
      final wireLogs = events
          .whereType<LogEmitted>()
          .map((e) => e.log)
          .where((e) => e.direction != LogDirection.event)
          .toList();
      expect(wireLogs, isNotEmpty);
      for (final log in wireLogs) {
        expect(log.terminalId, 'terminal-key');
        expect(log.messageId, isNotNull);
        expect(log.sequence, isNotNull);
        final frame = const Jt808Codec().decode(Jt808Codec.parseHex(log.hex));
        expect(frame.messageId, log.messageId);
        expect(frame.sequence, log.sequence);
      }
      await peer.close();
      await _until(() => client.phase == ConnectionPhase.failed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(platform.accepted, 1, reason: 'autoReconnect defaults to false');
    },
  );

  test(
    'stored code skips registration and sequence wraps from 65535 to zero',
    () async {
      final client = create(authCode: 'saved', initialSequence: 65535);
      final peer = await _online(platform, client);
      expect(peer.received.where((f) => f.messageId == 0x0100), isEmpty);
      expect(peer.received.first.sequence, 65535);
      expect(peer.received.first.body, 'saved'.codeUnits);
      await Future.wait([client.heartbeat(), client.heartbeat()]);
      final heartbeat = await peer.next(0x0002);
      expect(heartbeat.sequence, 0);
      expect(peer.received.where((f) => f.messageId == 0x0002), hasLength(1));
      await peer.ack(heartbeat);
      await client.sendLocation(LocationFix(recordedAt: DateTime.utc(2026)));
      expect((await peer.next(0x0200)).sequence, 1);
      final raw = const Jt808Codec().encode(
        Jt808Frame(
          messageId: 0x0900,
          phone: client.config.phone,
          sequence: 0x4af0,
          body: [0x7d, 0x7e],
        ),
      );
      await client.sendRaw(Jt808Codec.toHex(raw));
      final receivedRaw = await peer.next(0x0900);
      expect(receivedRaw.sequence, 0x4af0);
      expect(receivedRaw.body, [0x7d, 0x7e]);
      final wrongPhone = const Jt808Codec().encode(
        Jt808Frame(messageId: 2, phone: '000000000000', sequence: 0),
      );
      await expectLater(
        client.sendRaw(Jt808Codec.toHex(wrongPhone)),
        throwsFormatException,
      );
      await client.disconnect();
      expect(client.phase, ConnectionPhase.disconnected);
      await _until(() => peer.closed);
      await expectLater(client.heartbeat(), throwsStateError);
      await expectLater(client.sendRaw('GG'), throwsFormatException);
      expect(
        () => client.updateLocation(const LocationFix(latitude: 91)),
        throwsFormatException,
      );
    },
  );

  test(
    'parameter parsing is atomic, range checked, and queries expose only supported values',
    () async {
      final client = create(authCode: 'saved');
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final peer = await _online(platform, client);
      await peer.send(
        0x8103,
        _parameters({1: _dword(12), 0x29: _dword(7)}),
        sequence: 100,
      );
      expect((await peer.next(0x0001)).body, [0, 100, 0x81, 3, 0]);
      expect(client.config.heartbeatSeconds, 12);
      expect(client.config.locationIntervalSeconds, 7);
      await _settle();
      final changed = events.whereType<ParametersChanged>().single.parameters;
      expect(changed.keys, unorderedEquals([1, 0x29]));
      expect(changed[1], _dword(12));
      expect(() => changed[1]![0] = 4, throwsUnsupportedError);
      expect(() => changed[8] = [], throwsUnsupportedError);

      await peer.send(
        0x8103,
        _parameters({
          1: _dword(5),
          0x9999: [0],
        }),
        sequence: 101,
      );
      expect((await peer.next(0x0001)).body, [0, 101, 0x81, 3, 3]);
      expect(
        client.config.heartbeatSeconds,
        12,
        reason: 'unsupported parameter rejects entire update',
      );
      for (final value in [0, 3601]) {
        await peer.send(
          0x8103,
          _parameters({1: _dword(5), 0x29: _dword(value)}),
          sequence: 102,
        );
        expect((await peer.next(0x0001)).body.last, 2);
        expect(client.config.heartbeatSeconds, 12);
        expect(client.config.locationIntervalSeconds, 7);
      }
      await peer.send(0x8103, [
        2,
        ..._parameters({1: _dword(5)}).sublist(1),
        0,
        0,
      ], sequence: 103);
      expect((await peer.next(0x0001)).body.last, 2);
      expect(client.config.heartbeatSeconds, 12);
      await peer.send(0x8103, [1, 0, 0, 0, 1, 1, 5], sequence: 104);
      expect((await peer.next(0x0001)).body.last, 2);
      await peer.send(0x8103, [
        ..._parameters({1: _dword(5)}),
        9,
      ], sequence: 105);
      expect((await peer.next(0x0001)).body.last, 2);
      await peer.send(0x8104, const [], sequence: 110);
      final all = Jt808Reader((await peer.next(0x0104)).body);
      expect(all.word(), 110);
      expect(all.byte(), 2);
      expect(all.dword(), 1);
      expect(all.byte(), 4);
      expect(all.dword(), 12);
      expect(all.dword(), 0x29);
      expect(all.byte(), 4);
      expect(all.dword(), 7);
      all.requireEnd();
      await peer.send(0x8106, [
        2,
        ..._dword(0x9999),
        ..._dword(0x29),
      ], sequence: 111);
      expect((await peer.next(0x0104)).body, [
        0,
        111,
        1,
        ..._dword(0x29),
        4,
        ..._dword(7),
      ]);
      await _settle();
      expect(events.whereType<ParametersChanged>(), hasLength(1));
      expect(client.phase, ConnectionPhase.online);
    },
  );

  test(
    'GBK text, unknown commands, malformed bodies, and unsupported frame flags',
    () async {
      final client = create(authCode: 'saved');
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final peer = await _online(platform, client);
      // Two frames in one TCP write, including escaped bytes in the platform sequence.
      const codec = Jt808Codec();
      await peer.write([
        ...codec.encode(
          Jt808Frame(
            messageId: 0x8300,
            phone: client.config.phone,
            sequence: 0x7d,
            body: [4, ...Jt808MessageBodies.encodeGbk('请注意安全')],
          ),
        ),
        ...codec.encode(
          Jt808Frame(
            messageId: 0x8fff,
            phone: client.config.phone,
            sequence: 0x7e,
          ),
        ),
      ]);
      expect((await peer.next(0x0001)).body, [0, 0x7d, 0x83, 0, 0]);
      expect((await peer.next(0x0001)).body, [0, 0x7e, 0x8f, 0xff, 3]);
      await peer.send(0x8300, [4, 0xd6], sequence: 1);
      expect((await peer.next(0x0001)).body.last, 2);
      await peer.send(0x8201, [0], sequence: 2);
      expect((await peer.next(0x0001)).body.last, 2);
      final before = peer.received.length;
      await peer.send(0x8001, [0], sequence: 3);
      for (final flag in [0x40, 0x20, 0x04]) {
        final data = [0x82, 1, flag, 0, 1, 0x38, 0, 0x13, 0x80, 0, 0, 1];
        // No bytes requiring escaping in these headers/checksums.
        final crc = data.fold<int>(0, (a, b) => a ^ b);
        await peer.write([
          0x7e,
          ...data,
          if (crc == 0x7e || crc == 0x7d) 0x7d,
          if (crc == 0x7e) 2 else if (crc == 0x7d) 1 else crc,
          0x7e,
        ]);
      }
      await _settle();
      expect(peer.received.length, before);
      final logs = events.whereType<LogEmitted>().map((e) => e.log).toList();
      expect(logs.any((e) => e.message.contains('请注意安全')), isTrue);
      for (final reason in ['2019', 'Segmented', 'Encrypted']) {
        expect(
          logs.any((e) => e.isError && e.message.contains(reason)),
          isTrue,
        );
      }
      expect(client.phase, ConnectionPhase.online);
    },
  );

  test(
    'parameter heartbeat timer is real and heartbeat timeout closes transport',
    () async {
      final client = create(
        authCode: 'saved',
        responseTimeout: const Duration(milliseconds: 150),
      );
      final peer = await _online(platform, client);
      await peer.send(0x8103, _parameters({1: _dword(1), 0x29: _dword(1)}));
      expect((await peer.next(0x0001)).body.last, 0);
      client.updateLocation(
        LocationFix(latitude: 2.5, recordedAt: DateTime.utc(2026)),
      );
      final heartbeat = await peer.next(0x0002);
      final report = Jt808Reader((await peer.next(0x0200)).body);
      report.dword();
      report.dword();
      expect(report.dword(), 2500000);
      await peer.ack(
        heartbeat,
        requestSequence: (heartbeat.sequence + 1) & 0xffff,
      );
      await _until(() => client.phase == ConnectionPhase.failed);
      await _until(() => peer.closed);
    },
  );

  test(
    'temporary tracking validates interval and expires back to configured interval',
    () async {
      final client = create(authCode: 'saved');
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      final peer = await _online(platform, client);
      await peer.send(0x8202, [0, 2, ..._dword(1)]);
      expect((await peer.next(0x0001)).body.last, 2);
      await peer.send(0x8202, [0, 1, ..._dword(2)]);
      expect((await peer.next(0x0001)).body.last, 0);
      client.updateLocation(
        LocationFix(latitude: 1.25, recordedAt: DateTime.utc(2026)),
      );
      final tracked = Jt808Reader((await peer.next(0x0200)).body);
      tracked.dword();
      tracked.dword();
      expect(tracked.dword(), 1250000);
      await _until(
        () => events.whereType<LogEmitted>().any(
          (e) => e.log.message.contains('tracking expired'),
        ),
        timeout: const Duration(seconds: 3),
      );
      final count = peer.received.where((f) => f.messageId == 0x0200).length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        peer.received.where((f) => f.messageId == 0x0200),
        hasLength(count),
      );
      await peer.send(0x8202, [0, 1, ..._dword(10)]);
      expect((await peer.next(0x0001)).body.last, 0);
      await peer.send(0x8202, [0, 0]);
      expect((await peer.next(0x0001)).body.last, 0);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        peer.received.where((f) => f.messageId == 0x0200),
        hasLength(count),
      );
    },
  );

  test(
    'registration and authentication rejection and timeouts are event-only failures',
    () async {
      for (final mode in [
        'registration rejection',
        'registration timeout',
        'authentication rejection',
        'authentication timeout',
      ]) {
        final saved = mode.startsWith('authentication');
        final client = create(
          authCode: saved ? 'saved' : '',
          responseTimeout: const Duration(milliseconds: 150),
        );
        await client.connect();
        final peer = await platform.nextPeer();
        final request = await peer.next(saved ? 0x0102 : 0x0100);
        if (mode.endsWith('rejection')) {
          if (saved) {
            await peer.ack(request, result: 1);
          } else {
            await peer.send(
              0x8100,
              (Jt808Writer()
                    ..word(request.sequence)
                    ..byte(1))
                  .toBytes(),
            );
          }
        }
        await _until(() => client.phase == ConnectionPhase.failed);
        await _until(() => peer.closed);
        expect(client.config.authCode, saved ? 'saved' : '');
      }
    },
  );

  test(
    'opt-in reconnect, manual stop, connection cancellation, and disposal',
    () async {
      final client = create(authCode: 'saved', autoReconnect: true);
      final first = await _online(platform, client);
      await first.close();
      final second = await platform.nextPeer();
      final auth = await second.next(0x0102);
      await second.ack(auth);
      await _until(() => client.phase == ConnectionPhase.online);
      await second.close();
      await _until(() => client.phase == ConnectionPhase.failed);
      await client.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(platform.accepted, 2);
      expect(client.phase, ConnectionPhase.disconnected);

      final connecting = client.connect();
      await client.disconnect();
      await connecting;
      await _settle();
      expect(client.phase, ConnectionPhase.disconnected);
      // Consume a possible cancelled, accepted transport before the next connect.
      platform.discardClosedPeers();
      final third = await _online(platform, client);
      await client.dispose();
      await _until(() => third.closed);
      final count = platform.accepted;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(platform.accepted, count);
      await expectLater(client.connect(), throwsStateError);
      expect(
        () => client.updateLocation(const LocationFix()),
        throwsStateError,
      );
    },
  );

  test(
    'refused loopback connection reports failed without throwing a socket error',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final client = Jt808Client(
        config: TerminalConfig(id: 'refused', port: port),
        connectTimeout: const Duration(milliseconds: 300),
      );
      clients.add(client);
      final events = <ClientEvent>[];
      final subscription = client.events.listen(events.add);
      addTearDown(subscription.cancel);
      await client.connect();
      expect(client.phase, ConnectionPhase.failed);
      await _settle();
      expect(events.whereType<LogEmitted>().any((e) => e.log.isError), isTrue);
    },
  );
}

List<int> _dword(int value) => (Jt808Writer()..dword(value)).toBytes();
List<int> _parameters(Map<int, List<int>> values) {
  final body = Jt808Writer()..byte(values.length);
  for (final entry in values.entries) {
    body
      ..dword(entry.key)
      ..byte(entry.value.length)
      ..bytes(entry.value);
  }
  return body.toBytes();
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 40));
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('Loopback condition timed out', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<_Peer> _online(_Platform platform, Jt808Client client) async {
  await client.connect();
  final peer = await platform.nextPeer();
  final auth = await peer.next(0x0102);
  await peer.ack(auth);
  await _until(() => client.phase == ConnectionPhase.online);
  return peer;
}

class _Platform {
  _Platform(this.server) {
    subscription = server.listen((socket) {
      final peer = _Peer(socket);
      peers.add(peer);
      pending.add(peer);
    });
  }
  static Future<_Platform> bind() async =>
      _Platform(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
  final ServerSocket server;
  late final StreamSubscription<Socket> subscription;
  final peers = <_Peer>[], pending = <_Peer>[];
  int get port => server.port;
  int get accepted => peers.length;
  Future<_Peer> nextPeer() async {
    await _until(() => pending.isNotEmpty);
    return pending.removeAt(0);
  }

  void discardClosedPeers() => pending.removeWhere((peer) => peer.closed);
  Future<void> close() async {
    for (final peer in peers) {
      await peer.close();
    }
    await subscription.cancel();
    await server.close();
  }
}

class _Peer {
  _Peer(this.socket) {
    subscription = socket.listen(
      (data) {
        for (final packet in framer.add(data)) {
          final frame = codec.decode(packet);
          received.add(frame);
          pending.add(frame);
        }
      },
      onDone: () => closed = true,
      onError: (Object e) => closed = true,
    );
  }
  final Socket socket;
  final codec = const Jt808Codec();
  final framer = Jt808PacketFramer();
  final received = <Jt808Frame>[], pending = <Jt808Frame>[];
  late final StreamSubscription<List<int>> subscription;
  bool closed = false;
  int sequence = 1;
  Future<Jt808Frame> next(int id) async {
    await _until(() => pending.any((frame) => frame.messageId == id));
    final index = pending.indexWhere((frame) => frame.messageId == id);
    return pending.removeAt(index);
  }

  Future<void> send(int id, List<int> body, {int? sequence}) => write(
    codec.encode(
      Jt808Frame(
        messageId: id,
        phone: '013800138000',
        sequence: sequence ?? this.sequence++,
        body: body,
      ),
    ),
  );
  Future<void> ack(
    Jt808Frame request, {
    int? requestId,
    int? requestSequence,
    int result = 0,
  }) => send(
    0x8001,
    Jt808MessageBodies.generalResponse(
      requestSequence ?? request.sequence,
      requestId ?? request.messageId,
      result,
    ),
  );
  Future<void> write(List<int> bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await subscription.cancel();
    socket.destroy();
  }
}
