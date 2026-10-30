import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../../config/app_config.dart';
import '../../../../utils/failure.dart';
import '../../../../utils/task_runner.dart';
import '../../../../utils/typedefs.dart';
import '../../domain/route_planning.dart';
import 'map_coordinates.dart';

class HttpRoutePlanner implements RoutePlanner {
  HttpRoutePlanner(this._dio);
  HttpRoutePlanner._shared() : _dio = null;
  static final instance = HttpRoutePlanner._shared();
  DateTime? _lastDemoRequest;
  bool _publicRequestActive = false;
  final Dio? _dio;

  @override
  FutureEither<PlannedRoute> plan({
    required RoutePlanningSettings settings,
    required List<RouteWaypoint> waypoints,
    required RoutePlanningCancellation cancellation,
  }) => runTask(
    () async {
      if (settings.planningValidationKey case final key?) {
        throw UnknownFailure(key);
      }
      final origin = RoutePlanMetadata(
        provider: settings.provider,
        waypoints: waypoints,
      );
      if (!origin.isValid) throw const UnknownFailure('routing_points');
      final token = CancelToken();
      unawaited(cancellation.cancelled.then((_) => token.cancel()));
      if (cancellation.isCancelled) {
        throw const UnknownFailure('routing_cancelled');
      }
      var acquiredPublicRequest = false;
      try {
        final client = _dio ?? AppConfig.dio;
        final options = Options(
          headers: {
            'User-Agent':
                'JT808Simulator/1.0 (com.marks.flutter_jtt808_simulator)',
          },
          validateStatus: (status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 400),
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 25),
          // Stops and API keys must not enter the shared HTTP/error logger.
          extra: {'privateRequest': true},
          followRedirects: false,
        );
        late final Response<Object?> response;
        if (settings.provider == RoutingProvider.osrm) {
          final base = settings.osrmUrl.replaceFirst(RegExp(r'/+$'), '');
          if (settings.usesPublicOsrm) {
            final now = DateTime.now();
            if (_publicRequestActive ||
                (_lastDemoRequest != null &&
                    now.difference(_lastDemoRequest!) <
                        const Duration(seconds: 1))) {
              throw const ServerFailure('routing_rate');
            }
            _lastDemoRequest = now;
            _publicRequestActive = acquiredPublicRequest = true;
          }
          final coordinates = waypoints
              .map(
                (p) =>
                    '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}',
              )
              .join(';');
          response = await client.get<Object?>(
            '$base/route/v1/driving/$coordinates',
            queryParameters: {
              'overview': 'full',
              'geometries': 'geojson',
              'steps': 'false',
              'alternatives': 'false',
            },
            options: options,
            cancelToken: token,
          );
        } else {
          String coordinate(RouteWaypoint point) {
            final gcj = wgs84ToGcj02(LatLng(point.latitude, point.longitude));
            return '${gcj.longitude.toStringAsFixed(6)},${gcj.latitude.toStringAsFixed(6)}';
          }

          response = await client.get<Object?>(
            'https://restapi.amap.com/v5/direction/driving',
            queryParameters: {
              'key': settings.amapKey,
              'origin': coordinate(waypoints.first),
              'destination': coordinate(waypoints.last),
              if (waypoints.length > 2)
                'waypoints': waypoints
                    .sublist(1, waypoints.length - 1)
                    .map(coordinate)
                    .join(';'),
              'strategy': '32',
              'show_fields': 'polyline',
            },
            options: options,
            cancelToken: token,
          );
        }
        if (cancellation.isCancelled) {
          throw const UnknownFailure('routing_cancelled');
        }
        final data = response.data is String
            ? jsonDecode(response.data! as String)
            : response.data;
        final json = Map<String, Object?>.from(data as Map);
        final points = settings.provider == RoutingProvider.osrm
            ? _osrm(json)
            : _amap(json);
        if (points.length < 2 || points.every((p) => p == points.first)) {
          throw const ServerFailure('routing_no_route');
        }
        return PlannedRoute(points: points, origin: origin);
      } on Failure {
        rethrow;
      } on DioException catch (error) {
        // Do not forward DioException: its URL/body can expose Key and stops.
        throw switch (error.type) {
          DioExceptionType.cancel => const UnknownFailure('routing_cancelled'),
          _ when [401, 403].contains(error.response?.statusCode) =>
            const ServerFailure('routing_key'),
          _ when error.response?.statusCode == 429 => const ServerFailure(
            'routing_limit',
          ),
          _ => const NetworkFailure('routing_network'),
        };
      } catch (_) {
        throw const ServerFailure('routing_response');
      } finally {
        if (acquiredPublicRequest) _publicRequestActive = false;
      }
    },
    operation: 'Plan driving route',
    context: {'provider': settings.provider.name},
  );

  List<RouteWaypoint> _osrm(Map<String, Object?> json) {
    if (['NoRoute', 'NoSegment'].contains(json['code'])) {
      throw const ServerFailure('routing_no_route');
    }
    if (json['code'] == 'TooBig') throw const ServerFailure('routing_limit');
    if (json['code'] != 'Ok') throw const ServerFailure('routing_response');
    final routes = json['routes'] as List;
    if (routes.isEmpty) throw const ServerFailure('routing_no_route');
    final geometry = (routes.first as Map)['geometry'] as Map;
    if (geometry['type'] != 'LineString') {
      throw const ServerFailure('routing_response');
    }
    final points = <RouteWaypoint>[];
    for (final value in geometry['coordinates'] as List) {
      final pair = value as List;
      _append(
        points,
        RouteWaypoint((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
      );
    }
    return points;
  }

  List<RouteWaypoint> _amap(Map<String, Object?> json) {
    if (json['status'] != '1') {
      if ([
        '10003',
        '10004',
        '10010',
        '10019',
        '10020',
        '10021',
        '10044',
      ].contains(json['infocode'])) {
        throw const ServerFailure('routing_limit');
      }
      if ([
        '10001',
        '10005',
        '10006',
        '10007',
        '10009',
        '10012',
        '10013',
      ].contains(json['infocode'])) {
        throw const ServerFailure('routing_key');
      }
      throw const ServerFailure('routing_response');
    }
    final paths = (json['route'] as Map)['paths'] as List;
    if (paths.isEmpty) throw const ServerFailure('routing_no_route');
    final points = <RouteWaypoint>[];
    for (final step in (paths.first as Map)['steps'] as List) {
      for (final value in ((step as Map)['polyline'] as String).split(';')) {
        final pair = value.split(',');
        if (pair.length != 2) throw const ServerFailure('routing_response');
        final gcj = LatLng(double.parse(pair[1]), double.parse(pair[0]));
        if (!RouteWaypoint(gcj.latitude, gcj.longitude).isValid) {
          throw const ServerFailure('routing_response');
        }
        final wgs = gcj02ToWgs84(gcj);
        _append(points, RouteWaypoint(wgs.latitude, wgs.longitude));
      }
    }
    return points;
  }

  void _append(List<RouteWaypoint> points, RouteWaypoint point) {
    if (!point.isValid) throw const ServerFailure('routing_response');
    if (points.isNotEmpty && points.last == point) return;
    if (points.length >= 10000) throw const ServerFailure('routing_limit');
    points.add(point);
  }
}
