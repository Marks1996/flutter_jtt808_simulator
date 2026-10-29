import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/hive_simulator_repository.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jt808-storage-test-');
    Hive.init(directory.path);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'real Hive storage preserves terminals, credentials, routes and tasks across reopen',
    () async {
      final repository = HiveSimulatorRepository();
      expect((await repository.load()).terminals, isEmpty);
      final data = SimulatorWorkspace(
        terminals: const [TerminalConfig(id: 't', authCode: 'LOCAL-TEST')],
        routes: [
          RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Test polyline'),
        ],
        tasks: const [
          DriveTask(
            id: 'job',
            name: 'Test task',
            terminalId: 't',
            routeId: 'r',
          ),
        ],
        theme: 'dark',
      );
      await repository.save(data);
      await Hive.close();
      Hive.init(directory.path);
      final reopened = await HiveSimulatorRepository().load();
      expect(reopened.toJson(), data.toJson());
    },
  );
  test(
    'malformed persisted JSON is surfaced and never silently replaced',
    () async {
      final repository = HiveSimulatorRepository();
      await repository.load();
      const corrupt = '{broken workspace';
      await Hive.box<String>('simulator_workspace').put('workspace', corrupt);
      final controller = SimulatorController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.loadState.isFailure, isTrue);
      expect(Hive.box<String>('simulator_workspace').get('workspace'), corrupt);
    },
  );
}
