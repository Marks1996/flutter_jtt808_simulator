import 'dart:async';

import 'package:equatable/equatable.dart';

import '../../../utils/typedefs.dart';

enum RoutingProvider { osrm, amap }

class RoutePlanningSettings extends Equatable {
  const RoutePlanningSettings({
    this.provider = RoutingProvider.amap,
    this.osrmUrl = '',
    this.amapKey = '',
    this.amapAuthorized = false,
  });

  static const publicDemoUrl = 'https://router.project-osrm.org';
  static const fossgisDemoUrl = 'https://routing.openstreetmap.de/routed-car';

  /// Both services are public, keyless OSRM-compatible endpoints. These are
  /// explicit opt-in presets, never automatic fallbacks or setup defaults.
  bool get usesPublicOsrm =>
      provider == RoutingProvider.osrm && isPublicOsrmUrl(osrmUrl);

  static bool isPublicOsrmUrl(String url) => [
    'router.project-osrm.org',
    'routing.openstreetmap.de',
  ].contains(Uri.tryParse(url)?.host.toLowerCase());
  final bool amapAuthorized;

  final RoutingProvider provider;
  final String osrmUrl, amapKey;

  static String? validateOsrmUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                  '[::1]',
                ].contains(uri.host))) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s|[{}]').hasMatch(value)) {
      return 'routing_url';
    }
    return null;
  }

  // Credentials may be cleared and stored as an explicit unconfigured state.
  String? get validationKey => switch (provider) {
    RoutingProvider.osrm => osrmUrl.isEmpty ? null : validateOsrmUrl(osrmUrl),
    RoutingProvider.amap =>
      RegExp(r'\s').hasMatch(amapKey) ? 'routing_key' : null,
  };

  String? get planningValidationKey =>
      validationKey ??
      switch (provider) {
        RoutingProvider.osrm when osrmUrl.isEmpty => 'routing_url',
        RoutingProvider.amap when amapKey.isEmpty => 'routing_key',
        RoutingProvider.amap when !amapAuthorized =>
          'routing_amap_authorization',
        _ => null,
      };

  RoutePlanningSettings copyWith({
    RoutingProvider? provider,
    String? osrmUrl,
    String? amapKey,
    bool? amapAuthorized,
  }) => RoutePlanningSettings(
    provider: provider ?? this.provider,
    osrmUrl: osrmUrl ?? this.osrmUrl,
    amapKey: amapKey ?? this.amapKey,
    amapAuthorized: amapAuthorized ?? this.amapAuthorized,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'osrmUrl': osrmUrl,
    'amapKey': amapKey,
    'amapAuthorized': amapAuthorized,
  };

  factory RoutePlanningSettings.fromJson(Map<String, Object?> json) {
    final provider = RoutingProvider.values
        .where((value) => value.name == json['provider'])
        .firstOrNull;
    if (provider == null) throw const FormatException('routing_settings');
    final settings = RoutePlanningSettings(
      provider: provider,
      osrmUrl: json['osrmUrl'] as String? ?? '',
      amapKey: json['amapKey'] as String? ?? '',
      amapAuthorized: json['amapAuthorized'] as bool? ?? false,
    );
    if (settings.validationKey case final key?) throw FormatException(key);
    return settings;
  }

  @override
  List<Object?> get props => [provider, osrmUrl, amapKey, amapAuthorized];
}

/// WGS84 throughout the domain. Display/API coordinate conversion is in data.
class RouteWaypoint extends Equatable {
  const RouteWaypoint(this.latitude, this.longitude);
  final double latitude, longitude;
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
  factory RouteWaypoint.fromJson(Map<String, Object?> json) {
    final point = RouteWaypoint(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    );
    if (!point.isValid) throw const FormatException('invalid_coordinates');
    return point;
  }
  @override
  List<Object?> get props => [latitude, longitude];
}

/// Keeps the original stops so a planned route can be edited without treating
/// every geometry vertex as a routing waypoint. Contains no API credentials.
class RoutePlanMetadata {
  RoutePlanMetadata({
    required this.provider,
    required List<RouteWaypoint> waypoints,
  }) : waypoints = List.unmodifiable(waypoints);
  final RoutingProvider provider;
  final List<RouteWaypoint> waypoints;
  static const maxWaypoints = 18; // Origin + up to 16 stops + destination.
  bool get isValid =>
      waypoints.length >= 2 &&
      waypoints.length <= maxWaypoints &&
      waypoints.every((p) => p.isValid);
  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'waypoints': waypoints.map((p) => p.toJson()).toList(),
  };
  factory RoutePlanMetadata.fromJson(Map<String, Object?> json) {
    final provider = RoutingProvider.values
        .where((value) => value.name == json['provider'])
        .firstOrNull;
    if (provider == null) throw const FormatException('routing_response');
    final result = RoutePlanMetadata(
      provider: provider,
      waypoints: (json['waypoints'] as List)
          .map(
            (p) => RouteWaypoint.fromJson(Map<String, Object?>.from(p as Map)),
          )
          .toList(),
    );
    if (!result.isValid) throw const FormatException('routing_points');
    return result;
  }
}

class PlannedRoute {
  PlannedRoute({required List<RouteWaypoint> points, required this.origin})
    : points = List.unmodifiable(points);
  final List<RouteWaypoint> points;
  final RoutePlanMetadata origin;
}

/// Transport-independent cancellation, also used when stops/settings change.
class RoutePlanningCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

abstract interface class RoutePlanner {
  FutureEither<PlannedRoute> plan({
    required RoutePlanningSettings settings,
    required List<RouteWaypoint> waypoints,
    required RoutePlanningCancellation cancellation,
  });
}
