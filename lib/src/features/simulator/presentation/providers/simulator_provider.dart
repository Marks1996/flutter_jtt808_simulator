import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../utils/async_state.dart';
import '../../../../utils/failure.dart';
import '../../data/hive_simulator_repository.dart';
import '../../data/protocol/jt808_client.dart';
import '../../domain/route_player.dart';
import '../../domain/simulator_models.dart';
import '../../domain/simulator_repository.dart';

export '../../domain/simulator_models.dart';
export '../../domain/simulator_repository.dart';
export '../../domain/route_player.dart';

final simulatorProvider = ChangeNotifierProvider<SimulatorController>(
  (ref) => SimulatorController(HiveSimulatorRepository())..load(),
);

enum TaskPhase { stopped, running, paused, completed }

class TerminalRuntime {
  ConnectionPhase phase = ConnectionPhase.disconnected;
  String details = '';
  LocationFix location = const LocationFix();
  int sent = 0, received = 0;
  DateTime? lastSent;
  Map<int, List<int>> parameters = {};
  bool get busy =>
      phase != ConnectionPhase.disconnected && phase != ConnectionPhase.failed;
}

class TaskRuntime {
  TaskRuntime(this.player, {this.mileageOffset = 0});
  final RoutePlayer player;
  final double mileageOffset;
  final Stopwatch clock = Stopwatch();
  TaskPhase phase = TaskPhase.stopped;
}

class SimulatorController extends ChangeNotifier {
  SimulatorController(this.repository);
  final SimulatorRepository repository;
  SimulatorWorkspace _workspace = SimulatorWorkspace();
  RequestState<void> loadState = const RequestInitial();
  RequestState<void> saveState = const RequestInitial();
  SimulatorWorkspace get workspace => _workspace;
  List<TerminalConfig> get terminals => _workspace.terminals;
  List<DriveRoute> get routes => _workspace.routes;
  List<DriveTask> get tasks => _workspace.tasks;
  final Map<String, TerminalRuntime> _runtimes = {};
  final Map<String, TaskRuntime> taskRuntimes = {};
  final Map<String, Jt808Client> _clients = {};
  final Map<String, StreamSubscription<ClientEvent>> _subscriptions = {};
  final Map<String, int> _epochs = {};
  final List<ProtocolLog> _logs = [];
  List<ProtocolLog> get logs => List.unmodifiable(_logs);
  static const logLimit = 2000;
  int get onlineCount =>
      _runtimes.values.where((r) => r.phase == ConnectionPhase.online).length;
  int get sentCount => _runtimes.values.fold(0, (total, r) => total + r.sent);
  int get receivedCount =>
      _runtimes.values.fold(0, (total, r) => total + r.received);
  int get runningCount =>
      taskRuntimes.values.where((r) => r.phase == TaskPhase.running).length;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  int _id = 0;
  String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_id++}';
  TerminalRuntime runtime(String id) =>
      _runtimes.putIfAbsent(id, TerminalRuntime.new);
  TerminalConfig terminal(String id) => terminals.firstWhere((t) => t.id == id);
  DriveRoute route(String id) => routes.firstWhere((t) => t.id == id);

  Future<void> load() async {
    loadState = const RequestLoading();
    _changed();
    try {
      _workspace = await repository.load();
      for (final t in terminals) {
        runtime(t.id);
      }
      loadState = const RequestSuccess(null);
    } catch (error) {
      loadState = RequestFailure(
        CacheFailure('workspace_load_failed', error: error),
      );
    }
    _changed();
  }

  Future<void> _commit(SimulatorWorkspace next) async {
    _workspace = next;
    saveState = const RequestLoading();
    _changed();
    final snapshot = next;
    final write = _writes.then((_) => repository.save(snapshot));
    // The queue recovers after a failed disk write; the operation still reports it.
    _writes = write.catchError((Object _) {});
    try {
      await write;
      saveState = const RequestSuccess(null);
    } catch (error) {
      saveState = RequestFailure(
        CacheFailure('workspace_save_failed', error: error),
      );
    }
    _changed();
  }

  Future<void> retrySave() => _commit(_workspace);
  Future<void> setTheme(String theme) async {
    if (!['light', 'dark', 'system'].contains(theme)) {
      throw const FormatException('invalid_theme');
    }
    await _commit(_workspace.copyWith(theme: theme));
  }

  Future<void> saveTerminal(TerminalConfig config) async {
    if (config.validationKey case final key?) throw FormatException(key);
    if (runtime(config.id).busy) {
      throw const FormatException('disconnect_before_edit');
    }
    if (terminals.any((t) => t.id != config.id && t.phone == config.phone)) {
      throw const FormatException('duplicate_phone');
    }
    final list = [...terminals];
    final index = list.indexWhere((t) => t.id == config.id);
    if (index < 0) {
      list.add(config);
    } else {
      list[index] = config;
    }
    await _release(config.id);
    await _commit(_workspace.copyWith(terminals: list));
  }

  Future<void> deleteTerminal(String id) async {
    if (tasks.any((t) => t.terminalId == id)) {
      throw const FormatException('terminal_in_use');
    }
    await disconnect(id);
    await _release(id);
    _runtimes.remove(id);
    await _commit(
      _workspace.copyWith(
        terminals: terminals.where((t) => t.id != id).toList(),
      ),
    );
  }

  Future<void> saveRoute(DriveRoute value) async {
    if (tasks.any(
      (t) =>
          t.routeId == value.id &&
          taskRuntimes[t.id]?.phase == TaskPhase.running,
    )) {
      throw const FormatException('stop_before_edit');
    }
    RoutePlayer(
      value,
    ); // One shared validation for editor, playback, and imports.
    final list = [...routes];
    final index = list.indexWhere((r) => r.id == value.id);
    if (index < 0) {
      list.add(value);
    } else {
      list[index] = value;
    }
    for (final t in tasks.where((t) => t.routeId == value.id)) {
      taskRuntimes.remove(t.id);
    }
    await _commit(_workspace.copyWith(routes: list));
  }

  Future<void> deleteRoute(String id) async {
    if (tasks.any((t) => t.routeId == id)) {
      throw const FormatException('route_in_use');
    }
    await _commit(
      _workspace.copyWith(routes: routes.where((r) => r.id != id).toList()),
    );
  }

  Future<void> saveTask(DriveTask task) async {
    if (task.name.trim().isEmpty) throw const FormatException('required');
    if (!terminals.any((t) => t.id == task.terminalId) ||
        !routes.any((r) => r.id == task.routeId)) {
      throw const FormatException('task_dependencies');
    }
    if (taskRuntimes[task.id]?.phase == TaskPhase.running) {
      throw const FormatException('stop_before_edit');
    }
    final list = [...tasks];
    final index = list.indexWhere((t) => t.id == task.id);
    if (index < 0) {
      list.add(task);
    } else {
      list[index] = task;
    }
    taskRuntimes.remove(task.id);
    await _commit(_workspace.copyWith(tasks: list));
  }

  Future<void> deleteTask(String id) async {
    stopTask(id);
    taskRuntimes.remove(id);
    await _commit(
      _workspace.copyWith(tasks: tasks.where((t) => t.id != id).toList()),
    );
  }

  Future<void> connect(String id) async {
    final config = terminal(id);
    if (runtime(id).busy) return;
    final epoch = (_epochs[id] ?? 0) + 1;
    _epochs[id] = epoch;
    runtime(id).phase = ConnectionPhase.connecting;
    _changed();
    await _release(id);
    if (_disposed || _epochs[id] != epoch) return;
    final client = Jt808Client(
      config: config,
      initialLocation: runtime(id).location,
      locationProvider: () => _prepareLocation(id),
    );
    _clients[id] = client;
    _subscriptions[id] = client.events.listen((event) => _onEvent(id, event));
    await client.connect();
  }

  Future<void> disconnect(String id) async {
    _epochs[id] = (_epochs[id] ?? 0) + 1;
    _prepareLocation(id);
    for (final task in tasks.where((t) => t.terminalId == id)) {
      taskRuntimes[task.id]?.clock.stop();
    }
    for (final t in tasks.where((t) => t.terminalId == id)) {
      final r = taskRuntimes[t.id];
      if (r?.phase == TaskPhase.running) r!.phase = TaskPhase.paused;
    }
    await _clients[id]?.disconnect();
    runtime(id).phase = ConnectionPhase.disconnected;
    _changed();
  }

  Future<void> connectAll() async {
    await Future.wait(
      terminals.where((t) => !runtime(t.id).busy).map((t) => connect(t.id)),
    );
  }

  Future<void> disconnectAll() async {
    await Future.wait(terminals.map((t) => disconnect(t.id)));
  }

  void _onEvent(String id, ClientEvent event) {
    if (_disposed) return;
    final r = runtime(id);
    switch (event) {
      case ConnectionChanged(:final phase, :final details):
        _prepareLocation(id);
        r.phase = phase;
        r.details = details;
        for (final task in tasks.where((t) => t.terminalId == id)) {
          final run = taskRuntimes[task.id];
          if (run == null) continue;
          run.clock.stop();
          run.clock.reset();
          if (phase == ConnectionPhase.online &&
              run.phase == TaskPhase.running) {
            run.clock.start();
          } else if (phase == ConnectionPhase.failed &&
              !terminal(id).autoReconnect &&
              run.phase == TaskPhase.running) {
            run.phase = TaskPhase.paused;
            r.location = r.location.copyWith(speed: 0);
          }
        }
      case LogEmitted(:final log):
        _logs.add(log);
        if (_logs.length > logLimit) {
          _logs.removeRange(0, _logs.length - logLimit);
        }
        if (log.direction == LogDirection.sent) {
          r.sent++;
          if (log.messageId == 0x0200 || log.messageId == 0x0201) {
            r.lastSent = log.time;
          }
        }
        if (log.direction == LogDirection.received) r.received++;
      case AuthenticationCodeReceived(:final code):
        final updated = terminals
            .map((t) => t.id == id ? t.withAuthCode(code) : t)
            .toList();
        unawaited(_commit(_workspace.copyWith(terminals: updated)));
      case ParametersChanged(:final parameters):
        r.parameters = parameters;
        int parameter(int key, int fallback) =>
            parameters[key]?.fold<int>(
              0,
              (value, byte) => (value << 8) | byte,
            ) ??
            fallback;
        final config = terminal(id);
        final updated = TerminalConfig.fromJson({
          ...config.toJson(),
          'heartbeatSeconds': parameter(0x0001, config.heartbeatSeconds),
          'locationIntervalSeconds': parameter(
            0x0029,
            config.locationIntervalSeconds,
          ),
        });
        unawaited(
          _commit(
            _workspace.copyWith(
              terminals: terminals
                  .map((t) => t.id == id ? updated : t)
                  .toList(),
            ),
          ),
        );
    }
    _changed();
  }

  /// The TCP client owns report timers, including temporary tracking. Preparing
  /// a report advances the trajectory by real active time, never once per sender.
  LocationFix _prepareLocation(String id) {
    final runtime = this.runtime(id);
    for (final task in tasks.where((t) => t.terminalId == id)) {
      final run = taskRuntimes[task.id];
      if (run == null ||
          run.phase != TaskPhase.running ||
          !run.clock.isRunning) {
        continue;
      }
      final elapsed = run.clock.elapsed;
      run.clock.reset();
      final next = run.player
          .advance(elapsed)
          .copyWith(
            alarm: runtime.location.alarm,
            status: runtime.location.status,
            mileage: run.mileageOffset + run.player.travelledKm,
          );
      runtime.location = next.copyWith(status: next.effectiveStatus);
      if (run.player.finished) {
        run.phase = TaskPhase.completed;
        run.clock.stop();
      }
    }
    _changed();
    return runtime.location;
  }

  void updateLocation(String id, LocationFix location) {
    if (location.validationKey case final key?) throw FormatException(key);
    final normalized = location.copyWith(status: location.effectiveStatus);
    runtime(id).location = normalized;
    _clients[id]?.updateLocation(normalized);
    _changed();
  }

  Future<void> sendLocation(String id) async {
    if (runtime(id).phase != ConnectionPhase.online) {
      throw const FormatException('connect_first');
    }
    await _clients[id]!.sendLocation(_prepareLocation(id));
  }

  Future<void> heartbeat(String id) async {
    if (runtime(id).phase != ConnectionPhase.online) {
      throw const FormatException('connect_first');
    }
    await _clients[id]!.heartbeat();
  }

  Future<void> sendRaw(String id, String hex) async {
    if (runtime(id).phase != ConnectionPhase.online) {
      throw const FormatException('connect_first');
    }
    await _clients[id]!.sendRaw(hex);
  }

  Future<void> startTask(String id) async {
    final task = tasks.firstWhere((t) => t.id == id);
    if (tasks.any(
      (t) =>
          t.id != id &&
          t.terminalId == task.terminalId &&
          [
            TaskPhase.running,
            TaskPhase.paused,
          ].contains(taskRuntimes[t.id]?.phase),
    )) {
      throw const FormatException('terminal_task_busy');
    }
    var run = taskRuntimes[id];
    if (run == null ||
        run.phase == TaskPhase.completed ||
        run.phase == TaskPhase.stopped) {
      run = TaskRuntime(
        RoutePlayer(route(task.routeId), loop: task.loop),
        mileageOffset: runtime(task.terminalId).location.mileage,
      );
      taskRuntimes[id] = run;
    }
    run.phase = TaskPhase.running;
    run.clock.reset();
    if (runtime(task.terminalId).phase == ConnectionPhase.online) {
      run.clock.start();
    }
    final current = runtime(task.terminalId).location;
    updateLocation(
      task.terminalId,
      run.player.current.copyWith(
        alarm: current.alarm,
        status: current.status,
        mileage: run.mileageOffset + run.player.travelledKm,
      ),
    );
    try {
      await connect(task.terminalId);
    } catch (error) {
      run.phase = TaskPhase.paused;
      run.clock.stop();
      _changed();
      rethrow;
    }
    _changed();
  }

  void pauseTask(String id) {
    final task = tasks.firstWhere((t) => t.id == id);
    _prepareLocation(task.terminalId);
    taskRuntimes[id]?.clock.stop();
    taskRuntimes[id]?.phase = TaskPhase.paused;
    updateLocation(
      task.terminalId,
      runtime(task.terminalId).location.copyWith(speed: 0),
    );
  }

  void stopTask(String id) {
    final task = tasks.firstWhere((t) => t.id == id);
    _prepareLocation(task.terminalId);
    taskRuntimes[id]?.clock.stop();
    taskRuntimes[id]?.phase = TaskPhase.stopped;
    updateLocation(
      task.terminalId,
      runtime(task.terminalId).location.copyWith(speed: 0),
    );
  }

  void clearLogs() {
    _logs.clear();
    _changed();
  }

  String exportLogs({String? terminalId}) =>
      const JsonEncoder.withIndent('  ').convert(
        _logs
            .where((l) => terminalId == null || l.terminalId == terminalId)
            .map(
              (l) => {
                'time': l.time.toIso8601String(),
                'terminalId': l.terminalId,
                'direction': l.direction.name,
                'messageId': l.idHex,
                'sequence': l.sequence,
                'message': l.message,
                'hex': l.hex,
                'error': l.isError,
              },
            )
            .toList(),
      );
  String exportWorkspace() =>
      const JsonEncoder.withIndent('  ').convert(_workspace.toJson());
  Future<void> importWorkspace(String json) async {
    if (_runtimes.values.any((r) => r.busy)) {
      throw const FormatException('disconnect_before_import');
    }
    final imported = SimulatorWorkspace.fromJson(
      Map<String, Object?>.from(jsonDecode(json) as Map),
    );
    for (final id in _clients.keys.toList()) {
      await _release(id);
    }
    _runtimes.clear();
    taskRuntimes.clear();
    await _commit(imported);
  }

  Future<void> _release(String id) async {
    await _subscriptions.remove(id)?.cancel();
    await _clients.remove(id)?.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final run in taskRuntimes.values) {
      run.clock.stop();
    }
    for (final sub in _subscriptions.values) {
      unawaited(sub.cancel());
    }
    for (final client in _clients.values) {
      unawaited(client.dispose());
    }
    super.dispose();
  }
}
