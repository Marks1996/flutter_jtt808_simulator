import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_jtt808_simulator/src/features/simulator/data/maps/http_route_planner.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/maps/map_coordinates.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_repository.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_models.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/route_planning_provider.dart';
import 'package:flutter_jtt808_simulator/src/utils/async_state.dart';
import 'package:flutter_jtt808_simulator/src/utils/failure.dart';
import 'package:flutter_jtt808_simulator/src/utils/typedefs.dart';

const _osrmSettings = RoutePlanningSettings(
  provider: RoutingProvider.osrm,
  osrmUrl: RoutePlanningSettings.publicDemoUrl,
);
const _stops = [RouteWaypoint(39.9042, 116.4074), RouteWaypoint(39.91, 116.42)];

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply, {this.status = 200});
  final Object? reply;
  final int status;
  RequestOptions? request;
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    requests++;
    return ResponseBody.fromString(
      jsonEncode(reply),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DeferredAdapter extends _Adapter {
  _DeferredAdapter(super.reply);

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _PendingPlanner implements RoutePlanner {
  final requests =
      <
        ({
          RoutePlanningCancellation cancellation,
          Completer<Either<Failure, PlannedRoute>> result,
        })
      >[];
  @override
  FutureEither<PlannedRoute> plan({
    required RoutePlanningSettings settings,
    required List<RouteWaypoint> waypoints,
    required RoutePlanningCancellation cancellation,
  }) {
    final result = Completer<Either<Failure, PlannedRoute>>();
    requests.add((cancellation: cancellation, result: result));
    return result.future;
  }
}

Object _osrm(List<List<num>> coordinates) => {
  'code': 'Ok',
  'routes': [
    {
      'geometry': {'type': 'LineString', 'coordinates': coordinates},
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'old workspaces migrate routing settings and settings retain both providers',
    () {
      final json = SimulatorWorkspace().toJson()..remove('routing');
      final migrated = SimulatorWorkspace.fromJson(json);
      expect(migrated.routing, const RoutePlanningSettings());
      const settings = RoutePlanningSettings(
        provider: RoutingProvider.amap,
        amapKey: 'test-key',
        amapAuthorized: true,
        osrmUrl: 'https://routing.example.com/osrm',
      );
      final saved = migrated.copyWith(routing: settings, theme: 'dark');
      expect(
        SimulatorWorkspace.fromJson(
          jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
        ).routing,
        settings,
      );
      expect(
        settings.copyWith(provider: RoutingProvider.osrm).amapKey,
        'test-key',
      );
      expect(
        settings.copyWith(provider: RoutingProvider.osrm).osrmUrl,
        settings.osrmUrl,
      );
    },
  );

  test(
    'China defaults and missing legacy settings round-trip without foreign fallback',
    () {
      final fresh = SimulatorWorkspace();
      final legacy = fresh.toJson()
        ..remove('routing')
        ..remove('basemap');
      for (final workspace in [fresh, SimulatorWorkspace.fromJson(legacy)]) {
        expect(workspace.routing.provider, RoutingProvider.amap);
        expect(workspace.routing.amapKey, isEmpty);
        expect(workspace.routing.osrmUrl, isEmpty);
        expect(workspace.routing.validationKey, isNull);
        expect(workspace.routing.planningValidationKey, 'routing_key');
        expect(workspace.basemap.provider, BasemapProvider.tianditu);
        expect(workspace.basemap.tiandituKey, isEmpty);
        expect(
          SimulatorWorkspace.fromJson(
            jsonDecode(jsonEncode(workspace.toJson())) as Map<String, dynamic>,
          ).toJson(),
          workspace.toJson(),
        );
      }
      final explicitLegacy = fresh.copyWith(
        routing: _osrmSettings,
        basemap: const BasemapSettings(provider: BasemapProvider.openStreetMap),
      );
      final legacySettings = explicitLegacy.toJson();
      (legacySettings['basemap'] as Map<String, Object?>)
        ..remove('tiandituKey')
        ..remove('osmUrl');
      final restored = SimulatorWorkspace.fromJson(legacySettings);
      expect(restored.routing, _osrmSettings);
      expect(restored.basemap.provider, BasemapProvider.openStreetMap);
      expect(restored.basemap.osmUrl, BasemapSettings.legacyOsmUrl);
      expect(restored.routing.osrmUrl, 'https://router.project-osrm.org');
    },
  );

  test(
    'unconfigured and cleared routing credentials never send HTTP requests',
    () async {
      final adapter = _Adapter({});
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final planner = HttpRoutePlanner(dio);
      for (final settings in [
        const RoutePlanningSettings(),
        const RoutePlanningSettings(
          amapKey: 'saved-key',
          amapAuthorized: true,
        ).copyWith(amapKey: ''),
        _osrmSettings.copyWith(osrmUrl: ''),
      ]) {
        expect(settings.validationKey, isNull);
        expect(RoutePlanningSettings.fromJson(settings.toJson()), settings);
        final result = await planner.plan(
          settings: settings,
          waypoints: _stops,
          cancellation: RoutePlanningCancellation(),
        );
        final failure = result.swap().getOrElse(
          (_) => throw StateError('Expected failure'),
        );
        expect(
          failure.message,
          settings.provider == RoutingProvider.amap
              ? 'routing_key'
              : 'routing_url',
        );
        expect(adapter.request, isNull);
      }
    },
  );

  test(
    'routing URL validation rejects credentials and remote cleartext endpoints',
    () {
      for (final url in [
        'https://route.example.com',
        'https://route.example.com/prefix/',
        'http://localhost:5000',
        'http://127.0.0.1:5000',
      ]) {
        expect(RoutePlanningSettings.validateOsrmUrl(url), isNull, reason: url);
      }
      for (final url in [
        '',
        'http://route.example.com',
        'https://a:b@route.example.com',
        'https://route.example.com?key=secret',
        'https://route.example.com#fragment',
        'https://route.example.com/{x}',
        'https://route .example.com',
      ]) {
        expect(
          RoutePlanningSettings.validateOsrmUrl(url),
          'routing_url',
          reason: url,
        );
      }
      expect(
        const RoutePlanningSettings(
          provider: RoutingProvider.amap,
        ).planningValidationKey,
        'routing_key',
      );
      expect(
        () => RoutePlanningSettings.fromJson(const {'provider': 'unknown'}),
        throwsFormatException,
      );
    },
  );

  test('planned route metadata retains stops, not API keys, across JSON', () {
    final origin = RoutePlanMetadata(
      provider: RoutingProvider.amap,
      waypoints: _stops,
    );
    final route = DriveRoute(
      id: 'r',
      name: 'Planned',
      planning: origin,
      points: [
        for (final p in _stops)
          LocationFix(latitude: p.latitude, longitude: p.longitude, speed: 40),
      ],
    );
    final restored = DriveRoute.fromJson(
      jsonDecode(jsonEncode(route.toJson())) as Map<String, dynamic>,
    );
    expect(restored.planning!.provider, RoutingProvider.amap);
    expect(restored.planning!.waypoints, _stops);
    expect(jsonEncode(restored.toJson()), isNot(contains('Key')));
    expect(
      () => RoutePlanMetadata.fromJson({'provider': 'osrm', 'waypoints': []}),
      throwsFormatException,
    );
  });

  test(
    'map selection inverse preserves WGS84 through all supported display systems',
    () {
      const input = LatLng(39.9042, 116.4074);
      for (final provider in BasemapProvider.values) {
        final settings = BasemapSettings(
          provider: provider,
          customCoordinates: BasemapCoordinates.gcj02,
        );
        final roundtrip = basemapToWgs84(
          basemapCoordinates(input, settings),
          settings,
        );
        expect(
          roundtrip.latitude,
          closeTo(input.latitude, 1e-8),
          reason: provider.name,
        );
        expect(
          roundtrip.longitude,
          closeTo(input.longitude, 1e-8),
          reason: provider.name,
        );
      }
      const foreign = LatLng(51.5, -.1);
      expect(gcj02ToWgs84(foreign), foreign);
    },
  );

  test(
    'OSRM requests full GeoJSON in longitude latitude order with private logging',
    () async {
      final adapter = _Adapter(
        _osrm([
          [116.4074, 39.9042],
          [116.41, 39.905],
          [116.42, 39.91],
        ]),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final result = await HttpRoutePlanner(dio).plan(
        settings: const RoutePlanningSettings(
          provider: RoutingProvider.osrm,
          osrmUrl: 'https://routing.example.com/base/',
        ),
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      final route = result.getOrElse((failure) => throw failure);
      expect(route.points.first, _stops.first);
      expect(route.points.last, _stops.last);
      expect(
        adapter.request!.path,
        'https://routing.example.com/base/route/v1/driving/116.407400,39.904200;116.420000,39.910000',
      );
      expect(adapter.request!.queryParameters['geometries'], 'geojson');
      expect(adapter.request!.queryParameters['overview'], 'full');
      expect(adapter.request!.extra['privateRequest'], isTrue);
      expect(adapter.request!.followRedirects, isFalse);
    },
  );

  test(
    'Amap v5 sends GCJ02 stops and returns deduplicated WGS84 route geometry',
    () async {
      final adapter = _Adapter({
        'status': '1',
        'infocode': '10000',
        'route': {
          'paths': [
            {
              'steps': [
                {'polyline': '116.413642,39.905603;116.414,39.906'},
                {'polyline': '116.414,39.906;116.42,39.91'},
              ],
            },
          ],
        },
      });
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final result = await HttpRoutePlanner(dio).plan(
        settings: const RoutePlanningSettings(
          provider: RoutingProvider.amap,
          amapKey: 'test-key',
          amapAuthorized: true,
        ),
        waypoints: [
          _stops.first,
          const RouteWaypoint(39.906, 116.41),
          _stops.last,
        ],
        cancellation: RoutePlanningCancellation(),
      );
      final route = result.getOrElse((failure) => throw failure);
      expect(route.points.length, 3);
      expect(route.points.first.latitude, closeTo(39.9042, 1e-6));
      expect(route.points.first.longitude, closeTo(116.4074, 1e-6));
      expect(
        adapter.request!.path,
        'https://restapi.amap.com/v5/direction/driving',
      );
      expect(
        adapter.request!.queryParameters['origin'],
        '116.413642,39.905603',
      );
      expect(adapter.request!.queryParameters['show_fields'], 'polyline');
      expect(adapter.request!.queryParameters['waypoints'], isA<String>());
      expect(route.origin.waypoints.length, 3);
      expect(route.origin.provider, RoutingProvider.amap);
    },
  );

  for (final sample
      in <({Object data, String error, RoutingProvider provider, int status})>[
        (
          data: {'code': 'NoRoute'},
          error: 'routing_no_route',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: {'code': 'NoSegment'},
          error: 'routing_no_route',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: _osrm([
            [116, 39],
          ]),
          error: 'routing_no_route',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: _osrm([
            [116, 39],
            [181, 39],
          ]),
          error: 'routing_response',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: {'code': 'Ok', 'routes': <Object?>[]},
          error: 'routing_no_route',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: {'secret': 'test-key'},
          error: 'routing_response',
          provider: RoutingProvider.osrm,
          status: 200,
        ),
        (
          data: {'status': '0', 'infocode': '10001'},
          error: 'routing_key',
          provider: RoutingProvider.amap,
          status: 200,
        ),
        (
          data: {'status': '0', 'infocode': '10003'},
          error: 'routing_limit',
          provider: RoutingProvider.amap,
          status: 200,
        ),
        (
          data: {
            'status': '1',
            'route': {'paths': <Object?>[]},
          },
          error: 'routing_no_route',
          provider: RoutingProvider.amap,
          status: 200,
        ),
        (
          data: {'error': 'test-key'},
          error: 'routing_limit',
          provider: RoutingProvider.amap,
          status: 429,
        ),
        (
          data: {'error': 'test-key'},
          error: 'routing_key',
          provider: RoutingProvider.amap,
          status: 403,
        ),
      ]) {
    test(
      'routing maps ${sample.provider.name} ${sample.error} ${sample.data} safely',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _Adapter(sample.data, status: sample.status);
        addTearDown(dio.close);
        final result = await HttpRoutePlanner(dio).plan(
          settings: RoutePlanningSettings(
            provider: sample.provider,
            osrmUrl: RoutePlanningSettings.publicDemoUrl,
            amapKey: 'test-key',
            amapAuthorized: true,
          ),
          waypoints: _stops,
          cancellation: RoutePlanningCancellation(),
        );
        final failure = result.swap().getOrElse(
          (_) => throw StateError('Expected failure'),
        );
        expect(failure.message, sample.error);
        expect(failure.error, isNull);
        expect('$failure', isNot(contains('test-key')));
      },
    );
  }

  test('Amap requests require explicit permission confirmation', () async {
    final adapter = _Adapter({});
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    const settings = RoutePlanningSettings(
      provider: RoutingProvider.amap,
      amapKey: 'test-key',
    );
    expect(settings.validationKey, isNull);
    expect(settings.planningValidationKey, 'routing_amap_authorization');
    final result = await HttpRoutePlanner(dio).plan(
      settings: settings,
      waypoints: _stops,
      cancellation: RoutePlanningCancellation(),
    );
    expect(
      result
          .swap()
          .getOrElse((_) => throw StateError('Expected failure'))
          .message,
      'routing_amap_authorization',
    );
    expect(adapter.request, isNull);
  });

  test(
    'OSRM HTTP 400 no-segment errors are recoverable routing errors',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter({'code': 'NoSegment'}, status: 400);
      addTearDown(dio.close);
      final result = await HttpRoutePlanner(dio).plan(
        settings: _osrmSettings,
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      expect(
        result
            .swap()
            .getOrElse((_) => throw StateError('Expected failure'))
            .message,
        'routing_no_route',
      );
    },
  );

  test(
    'public demo requests are locally limited without retrying automatically',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          _osrm([
            [116.4074, 39.9042],
            [116.42, 39.91],
          ]),
        );
      addTearDown(dio.close);
      final planner = HttpRoutePlanner(dio);
      final first = await planner.plan(
        settings: _osrmSettings,
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      expect(first.isRight(), isTrue);
      final second = await planner.plan(
        settings: _osrmSettings,
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      expect(
        second
            .swap()
            .getOrElse((_) => throw StateError('Expected failure'))
            .message,
        'routing_rate',
      );
    },
  );

  test(
    'public OSRM identification uses exact hosts and the active provider',
    () {
      for (final url in [
        RoutePlanningSettings.publicDemoUrl,
        '${RoutePlanningSettings.publicDemoUrl}/',
        RoutePlanningSettings.fossgisDemoUrl,
        '${RoutePlanningSettings.fossgisDemoUrl}///',
        'https://ROUTING.OPENSTREETMAP.DE/routed-car/',
      ]) {
        expect(RoutePlanningSettings.isPublicOsrmUrl(url), isTrue, reason: url);
        final settings = _osrmSettings.copyWith(osrmUrl: url);
        expect(settings.usesPublicOsrm, isTrue, reason: url);
        expect(
          settings.copyWith(provider: RoutingProvider.amap).usesPublicOsrm,
          isFalse,
          reason: url,
        );
      }
      for (final url in [
        '',
        'not a URL',
        'https://router.project-osrm.org.evil.example',
        'https://routing.openstreetmap.de.evil.example/routed-car',
        'https://evil.example/router.project-osrm.org',
        'https://evil.example/routing.openstreetmap.de/routed-car',
        'https://router.project-osrm.org@evil.example',
        'https://self-hosted.example/osrm',
        'http://localhost:5000',
      ]) {
        expect(
          RoutePlanningSettings.isPublicOsrmUrl(url),
          isFalse,
          reason: url,
        );
        expect(
          _osrmSettings.copyWith(osrmUrl: url).usesPublicOsrm,
          isFalse,
          reason: url,
        );
      }
    },
  );

  test(
    'FOSSGIS keeps routed-car prefix and requests full keyless GeoJSON',
    () async {
      final adapter = _Adapter(
        _osrm([
          [116.4074, 39.9042],
          [116.41, 39.905],
          [116.42, 39.91],
        ]),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final result = await HttpRoutePlanner(dio).plan(
        settings: _osrmSettings.copyWith(
          osrmUrl: '${RoutePlanningSettings.fossgisDemoUrl}/',
          amapKey: 'retained-private-amap-key',
          amapAuthorized: true,
        ),
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      final route = result.getOrElse((failure) => throw failure);
      expect(route.points, [
        _stops.first,
        const RouteWaypoint(39.905, 116.41),
        _stops.last,
      ]);
      expect(route.origin.provider, RoutingProvider.osrm);
      expect(adapter.request!.method, 'GET');
      expect(
        adapter.request!.path,
        'https://routing.openstreetmap.de/routed-car/route/v1/driving/116.407400,39.904200;116.420000,39.910000',
      );
      expect(adapter.request!.queryParameters, {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
        'alternatives': 'false',
      });
      expect(
        adapter.request!.uri.toString(),
        isNot(contains('retained-private')),
      );
      expect(adapter.request!.extra['privateRequest'], isTrue);
      expect(adapter.request!.followRedirects, isFalse);
      expect(adapter.requests, 1);
    },
  );

  for (final firstUrl in [
    RoutePlanningSettings.publicDemoUrl,
    RoutePlanningSettings.fossgisDemoUrl,
  ]) {
    test(
      'public OSRM endpoints share a rate limit starting with $firstUrl',
      () async {
        final adapter = _Adapter(
          _osrm([
            [116.4074, 39.9042],
            [116.42, 39.91],
          ]),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(dio.close);
        final planner = HttpRoutePlanner(dio);
        expect(
          (await planner.plan(
            settings: _osrmSettings.copyWith(osrmUrl: firstUrl),
            waypoints: _stops,
            cancellation: RoutePlanningCancellation(),
          )).isRight(),
          isTrue,
        );
        final second = await planner.plan(
          settings: _osrmSettings.copyWith(
            osrmUrl: firstUrl == RoutePlanningSettings.publicDemoUrl
                ? RoutePlanningSettings.fossgisDemoUrl
                : RoutePlanningSettings.publicDemoUrl,
          ),
          waypoints: _stops,
          cancellation: RoutePlanningCancellation(),
        );
        expect(
          second
              .swap()
              .getOrElse((_) => throw StateError('Expected failure'))
              .message,
          'routing_rate',
        );
        expect(
          adapter.requests,
          1,
          reason: 'Rejected requests must not retry.',
        );
        final privateResult = await planner.plan(
          settings: _osrmSettings.copyWith(
            osrmUrl: 'https://private.example/osrm',
          ),
          waypoints: _stops,
          cancellation: RoutePlanningCancellation(),
        );
        expect(privateResult.isRight(), isTrue);
        expect(adapter.requests, 2);
      },
    );
  }

  test('self-hosted OSRM requests are not limited or serialized', () async {
    final adapter = _DeferredAdapter(
      _osrm([
        [116.4074, 39.9042],
        [116.42, 39.91],
      ]),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final planner = HttpRoutePlanner(dio);
    final settings = _osrmSettings.copyWith(
      osrmUrl: 'http://localhost:5000/osrm',
    );
    final first = planner.plan(
      settings: settings,
      waypoints: _stops,
      cancellation: RoutePlanningCancellation(),
    );
    await adapter.started.future;
    final second = await planner.plan(
      settings: settings,
      waypoints: _stops,
      cancellation: RoutePlanningCancellation(),
    );
    expect(second.isRight(), isTrue);
    adapter.release.complete();
    expect((await first).isRight(), isTrue);
    expect(adapter.requests, 2);
  });

  test(
    'public in-flight lock survives rejection and releases after success',
    () async {
      final adapter = _DeferredAdapter(
        _osrm([
          [116.4074, 39.9042],
          [116.42, 39.91],
        ]),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final planner = HttpRoutePlanner(dio);
      FutureEither<PlannedRoute> plan(String url) => planner.plan(
        settings: _osrmSettings.copyWith(osrmUrl: url),
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      final first = plan(RoutePlanningSettings.publicDemoUrl);
      await adapter.started.future;
      // Cross the start-to-start interval: only the active request now blocks.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      for (var i = 0; i < 2; i++) {
        final rejected = await plan(RoutePlanningSettings.fossgisDemoUrl);
        expect(
          rejected
              .swap()
              .getOrElse((_) => throw StateError('Expected failure'))
              .message,
          'routing_rate',
        );
      }
      adapter.release.complete();
      expect((await first).isRight(), isTrue);
      expect(
        (await plan(RoutePlanningSettings.fossgisDemoUrl)).isRight(),
        isTrue,
      );
      expect(adapter.requests, 2);
    },
  );

  for (final status in [200, 503]) {
    test(
      'public in-flight lock releases after response failure $status',
      () async {
        final adapter = _Adapter({'invalid': 'response'}, status: status);
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(dio.close);
        final planner = HttpRoutePlanner(dio);
        FutureEither<PlannedRoute> plan(String url) => planner.plan(
          settings: _osrmSettings.copyWith(osrmUrl: url),
          waypoints: _stops,
          cancellation: RoutePlanningCancellation(),
        );
        expect(
          (await plan(RoutePlanningSettings.publicDemoUrl)).isLeft(),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        final next = await plan(RoutePlanningSettings.fossgisDemoUrl);
        expect(
          next
              .swap()
              .getOrElse((_) => throw StateError('Expected failure'))
              .message,
          status == 200 ? 'routing_response' : 'routing_network',
        );
        expect(adapter.requests, 2);
      },
    );
  }

  test('public in-flight lock releases after cancellation', () async {
    final adapter = _DeferredAdapter(
      _osrm([
        [116.4074, 39.9042],
        [116.42, 39.91],
      ]),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final planner = HttpRoutePlanner(dio);
    final cancellation = RoutePlanningCancellation();
    final first = planner.plan(
      settings: _osrmSettings,
      waypoints: _stops,
      cancellation: cancellation,
    );
    await adapter.started.future;
    cancellation.cancel();
    final cancelled = await first;
    expect(
      cancelled
          .swap()
          .getOrElse((_) => throw StateError('Expected failure'))
          .message,
      'routing_cancelled',
    );
    adapter.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final next = await planner.plan(
      settings: _osrmSettings.copyWith(
        osrmUrl: RoutePlanningSettings.fossgisDemoUrl,
      ),
      waypoints: _stops,
      cancellation: RoutePlanningCancellation(),
    );
    expect(next.isRight(), isTrue);
    expect(adapter.requests, 2);
  });

  test(
    'oversized route is rejected rather than silently truncating road geometry',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          _osrm([
            for (var i = 0; i < 10001; i++) [116 + i * .00001, 39],
          ]),
        );
      addTearDown(dio.close);
      final result = await HttpRoutePlanner(dio).plan(
        settings: _osrmSettings,
        waypoints: _stops,
        cancellation: RoutePlanningCancellation(),
      );
      expect(
        result
            .swap()
            .getOrElse((_) => throw StateError('Expected failure'))
            .message,
        'routing_limit',
      );
    },
  );

  test(
    'cancelled request sends nothing and waypoint count is validated',
    () async {
      final adapter = _Adapter({});
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final cancellation = RoutePlanningCancellation()..cancel();
      final result = await HttpRoutePlanner(dio).plan(
        settings: _osrmSettings,
        waypoints: _stops,
        cancellation: cancellation,
      );
      expect(
        result
            .swap()
            .getOrElse((_) => throw StateError('Expected failure'))
            .message,
        'routing_cancelled',
      );
      expect(adapter.request, isNull);
    },
  );

  test(
    'changing stops cancels old requests and ignores late results',
    () async {
      final planner = _PendingPlanner();
      final draft = RoutePlanningController(planner, waypoints: _stops);
      addTearDown(draft.dispose);
      final first = draft.plan(_osrmSettings);
      expect(draft.state.isLoading, isTrue);
      draft.update(1, const RouteWaypoint(39.92, 116.43));
      expect(planner.requests.first.cancellation.isCancelled, isTrue);
      expect(draft.state.isInitial, isTrue);
      final second = draft.plan(_osrmSettings);
      final current = PlannedRoute(
        points: draft.waypoints,
        origin: RoutePlanMetadata(
          provider: RoutingProvider.osrm,
          waypoints: draft.waypoints,
        ),
      );
      planner.requests.last.result.complete(right(current));
      await second;
      planner.requests.first.result.complete(
        left(const NetworkFailure('routing_network')),
      );
      await first;
      expect((draft.state as RequestSuccess<PlannedRoute>).data, same(current));
      draft.move(1, -1);
      expect(draft.waypoints.first, current.points.last);
      expect(draft.state.isInitial, isTrue);
      draft.replace(_stops);
      expect(draft.hasChanges, isFalse);
    },
  );

  test(
    'disposing the visual draft cancels an active request without notifying again',
    () async {
      final planner = _PendingPlanner();
      final draft = RoutePlanningController(planner, waypoints: _stops);
      final pending = draft.plan(_osrmSettings);
      draft.dispose();
      expect(planner.requests.single.cancellation.isCancelled, isTrue);
      planner.requests.single.result.complete(
        left(const NetworkFailure('routing_network')),
      );
      await pending;
    },
  );
}
