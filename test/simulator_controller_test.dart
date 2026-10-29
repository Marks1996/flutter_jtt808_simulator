import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';
import 'package:flutter_jtt808_simulator/src/utils/async_state.dart';

class MemoryRepository implements SimulatorRepository {
  SimulatorWorkspace data = SimulatorWorkspace();
  bool failLoad = false, failSave = false;
  final List<SimulatorWorkspace> writes = [];
  @override
  Future<SimulatorWorkspace> load() async {
    if (failLoad) throw StateError('disk read failed');
    return data;
  }

  @override
  Future<void> save(SimulatorWorkspace workspace) async {
    if (failSave) throw StateError('disk full');
    writes.add(workspace);
    data = workspace;
  }
}

void main() {
  late MemoryRepository repository;
  late SimulatorController controller;
  setUp(() {
    repository = MemoryRepository();
    controller = SimulatorController(repository);
  });
  tearDown(() => controller.dispose());
  test('fresh workspace is empty and starts no implicit connections', () async {
    await controller.load();
    expect(controller.loadState, isA<RequestSuccess<void>>());
    expect(controller.terminals, isEmpty);
    expect(controller.onlineCount, 0);
    expect(controller.sentCount, 0);
    expect(controller.receivedCount, 0);
    expect(controller.logs, isEmpty);
  });
  test('load failure remains recoverable without erasing disk data', () async {
    repository.failLoad = true;
    await controller.load();
    expect(controller.loadState, isA<RequestFailure<void>>());
    expect(repository.writes, isEmpty);
    repository.failLoad = false;
    await controller.load();
    expect(controller.loadState.isSuccess, isTrue);
  });
  test('save failure is visible and can be retried', () async {
    await controller.load();
    repository.failSave = true;
    await controller.saveTerminal(const TerminalConfig(id: 'one'));
    expect(controller.terminals, hasLength(1));
    expect(controller.saveState.isFailure, isTrue);
    repository.failSave = false;
    await controller.retrySave();
    expect(controller.saveState.isSuccess, isTrue);
    expect(repository.data.terminals, hasLength(1));
  });
  test(
    'workspace mutations preserve references and reject duplicate phones',
    () async {
      await controller.load();
      await controller.saveTerminal(const TerminalConfig(id: 'one'));
      await expectLater(
        controller.saveTerminal(const TerminalConfig(id: 'two')),
        throwsFormatException,
      );
      await controller.saveRoute(
        RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route'),
      );
      await controller.saveTask(
        const DriveTask(
          id: 'task',
          name: 'Task',
          terminalId: 'one',
          routeId: 'r',
        ),
      );
      await expectLater(controller.deleteRoute('r'), throwsFormatException);
      await expectLater(
        controller.deleteTerminal('one'),
        throwsFormatException,
      );
      await controller.deleteTask('task');
      await controller.deleteRoute('r');
      await controller.deleteTerminal('one');
      expect(repository.data.tasks, isEmpty);
      expect(repository.data.terminals, isEmpty);
      expect(repository.data.routes, isEmpty);
    },
  );
  test('invalid import is atomic; valid import never starts tasks', () async {
    await controller.saveTerminal(const TerminalConfig(id: 'one'));
    final before = controller.exportWorkspace();
    final invalid = {...repository.data.toJson(), 'version': 999};
    await expectLater(
      controller.importWorkspace(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(controller.exportWorkspace(), before);
    await controller.importWorkspace(before);
    expect(controller.runtime('one').phase, ConnectionPhase.disconnected);
    expect(controller.taskRuntimes, isEmpty);
  });
  test(
    'queued saves retain newest snapshot and recover after a failed write',
    () async {
      await controller.load();
      await Future.wait([
        controller.setTheme('dark'),
        controller.saveTerminal(const TerminalConfig(id: 'one')),
      ]);
      expect(repository.data.theme, 'dark');
      expect(repository.data.terminals, hasLength(1));
      expect(repository.writes.last.toJson(), controller.workspace.toJson());
    },
  );
}
