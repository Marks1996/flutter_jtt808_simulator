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
        routing: const RoutePlanningSettings(
          provider: RoutingProvider.amap,
          amapKey: 'test-key',
          osrmUrl: 'https://routing.example.com',
        ),
        basemap: const BasemapSettings(
          enabled: false,
          provider: BasemapProvider.custom,
          tiandituKey: 'retained-tianditu-key',
          amapUrl: 'https://amap.example.com/{z}/{x}/{y}.png',
          baiduUrl: 'https://baidu.example.com/{z}/{x}/{y}.png',
          customUrl: 'https://tiles.example.com/{z}/{x}/{y}.png',
          customAttribution: '© Test source',
          customCoordinates: BasemapCoordinates.gcj02,
        ),
      );
      await repository.save(data);
      await Hive.close();
      Hive.init(directory.path);
      final reopened = await HiveSimulatorRepository().load();
      expect(reopened.toJson(), data.toJson());
    },
  );
  test(
    'fresh domestic settings and explicitly cleared Keys survive real Hive reopen',
    () async {
      final repository = HiveSimulatorRepository();
      final fresh = await repository.load();
      expect(fresh.basemap.provider, BasemapProvider.tianditu);
      expect(fresh.routing.provider, RoutingProvider.amap);
      final controller = SimulatorController(repository);
      await controller.load();
      await controller.setBasemap(
        const BasemapSettings(tiandituKey: 'test-own-key'),
      );
      await controller.setRouting(
        const RoutePlanningSettings(
          amapKey: 'test-own-key',
          amapAuthorized: true,
        ),
      );
      await controller.setBasemap(
        controller.workspace.basemap.copyWith(tiandituKey: ''),
      );
      await controller.setRouting(
        controller.workspace.routing.copyWith(amapKey: ''),
      );
      expect(controller.saveState.isSuccess, isTrue);
      final expected = controller.workspace.toJson();
      controller.dispose();
      await Hive.close();
      Hive.init(directory.path);
      final reopened = await HiveSimulatorRepository().load();
      expect(reopened.toJson(), expected);
      expect(reopened.basemap.enabled, isTrue);
      expect(reopened.basemap.provider, BasemapProvider.tianditu);
      expect(reopened.basemap.configurationKey, 'tianditu_key_required');
      expect(reopened.routing.provider, RoutingProvider.amap);
      expect(reopened.routing.amapKey, isEmpty);
      expect(reopened.routing.osrmUrl, isEmpty);
      expect(reopened.routing.planningValidationKey, 'routing_key');
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
