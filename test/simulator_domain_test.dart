import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/route_player.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_models.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_repository.dart';

void main() {
  group('2013 terminal validation', () {
    test('defaults match reference format and server, never auto-connect', () {
      const value = TerminalConfig(id: 'one');
      expect(value.validationKey, isNull);
      expect(value.port, 7100);
      expect(value.autoReconnect, isFalse);
      expect(const LocationFix().status, 0x00040003);
    });
    test(
      'rejects out-of-range port, short BCD phone, and truncating identities',
      () {
        expect(
          const TerminalConfig(id: 'one', port: 65536).validationKey,
          'invalid_port',
        );
        expect(
          const TerminalConfig(id: 'one', phone: '13800138000').validationKey,
          'invalid_phone',
        );
        expect(
          const TerminalConfig(id: 'one', terminalId: 'ABCDEFGH').validationKey,
          'invalid_identity',
        );
        expect(
          const TerminalConfig(id: 'one', manufacturer: 'ABCDEF').validationKey,
          'invalid_identity',
        );
        expect(
          const TerminalConfig(
            id: 'one',
            locationIntervalSeconds: 0,
          ).validationKey,
          'invalid_interval',
        );
      },
    );
  });
  group('explicit coordinate CSV', () {
    test('round-trips the clearly illustrative polyline', () {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Example');
      expect(route.points, hasLength(5));
      expect(route.distanceKm, greaterThan(1));
      final roundTrip = RouteCsv.parse(
        RouteCsv.encode(route),
        id: 'r',
        name: route.name,
      );
      expect(roundTrip.toJson(), route.toJson());
    });
    test('rejects unlabelled, BD09, GCJ02, invalid and stationary data', () {
      for (final text in [
        '39,116,40\n40,116,40',
        '# BD09\n39,116,40\n40,116,40',
        '# GCJ02\n39,116,40\n40,116,40',
        '# WGS84\n91,116,40\n40,116,40',
        '# WGS84\n39,116,0\n40,116,40',
        '# WGS84\nNaN,116,40\n40,116,40',
        '# WGS84\n39,116,40\n39,116,40',
      ]) {
        expect(
          () => RouteCsv.parse(text, id: 'r', name: 'Route'),
          throwsFormatException,
          reason: text,
        );
      }
    });
  });
  group('time and speed based route playback', () {
    final route = DriveRoute(
      id: 'r',
      name: 'Equator',
      points: const [
        LocationFix(latitude: 0, longitude: 0, speed: 36),
        LocationFix(latitude: 0, longitude: 0.01, speed: 36),
        LocationFix(latitude: 0.01, longitude: 0.01, speed: 36),
      ],
    );
    test('moves 100 metres in ten seconds at 36 km/h', () {
      final player = RoutePlayer(route);
      final fix = player.advance(const Duration(seconds: 10));
      expect(player.travelledKm, closeTo(0.1, 0.000001));
      expect(fix.longitude, closeTo(0.0008993, 0.000001));
      expect(fix.direction, 90);
      expect(player.progress, greaterThan(0));
      expect(player.finished, isFalse);
    });
    test('consumes segment transitions and stops at the exact final point', () {
      final player = RoutePlayer(route);
      final end = player.advance(const Duration(hours: 1));
      expect(player.finished, isTrue);
      expect(player.progress, 1);
      expect(end.latitude, 0.01);
      expect(end.longitude, 0.01);
      expect(end.speed, 0);
      expect(end.mileage, closeTo(route.distanceKm, 0.000001));
      expect(player.advance(const Duration(hours: 1)).mileage, end.mileage);
    });
    test('crosses the antimeridian by the short geographic path', () {
      final player = RoutePlayer(
        DriveRoute(
          id: 'dateline',
          name: 'Dateline',
          points: const [
            LocationFix(latitude: 0, longitude: 179.9, speed: 100),
            LocationFix(latitude: 0, longitude: -179.9, speed: 100),
          ],
        ),
      );
      final point = player.advance(const Duration(minutes: 4));
      expect(point.longitude.abs(), greaterThan(179.8));
    });
    test('loop mileage continues instead of resetting', () {
      final player = RoutePlayer(route, loop: true);
      player.advance(const Duration(seconds: 250));
      expect(player.finished, isFalse);
      expect(player.travelledKm, closeTo(2.5, 0.000001));
    });
  });
  test('workspace round-trips without resuming connections or tasks', () {
    final data = SimulatorWorkspace(
      terminals: const [TerminalConfig(id: 't')],
      routes: [RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Example')],
      tasks: const [
        DriveTask(id: 'task', name: 'Task', terminalId: 't', routeId: 'r'),
      ],
      theme: 'dark',
    );
    expect(SimulatorWorkspace.fromJson(data.toJson()).toJson(), data.toJson());
    expect(
      () => SimulatorWorkspace.fromJson({...data.toJson(), 'version': 99}),
      throwsFormatException,
    );
    expect(
      () => SimulatorWorkspace.fromJson({...data.toJson(), 'terminals': []}),
      throwsFormatException,
    );
  });
}
