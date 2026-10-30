import 'dart:math' as math;

import 'route_planning.dart';

/// The simulator intentionally targets the same 2013 protocol as the reference.
enum ConnectionPhase {
  disconnected,
  connecting,
  registering,
  authenticating,
  online,
  failed,
}

enum LogDirection { sent, received, event }

class TerminalConfig {
  const TerminalConfig({
    required this.id,
    this.name = 'JT808-001',
    this.host = '127.0.0.1',
    this.port = 7100,
    this.phone = '013800138000',
    this.province = 1,
    this.city = 1,
    this.manufacturer = 'CHINA',
    this.model = 'FLUTTER-808',
    this.terminalId = '0000001',
    this.plate = 'TEST001',
    this.plateColor = 1,
    this.authCode = '',
    this.heartbeatSeconds = 30,
    this.locationIntervalSeconds = 5,
    this.autoReconnect = false,
  });

  final String id,
      name,
      host,
      phone,
      manufacturer,
      model,
      terminalId,
      plate,
      authCode;
  final int port,
      province,
      city,
      plateColor,
      heartbeatSeconds,
      locationIntervalSeconds;
  final bool autoReconnect;

  String? get validationKey {
    if (name.trim().isEmpty || host.trim().isEmpty) return 'required';
    if (port < 1 || port > 65535) return 'invalid_port';
    if (!RegExp(r'^\d{12}$').hasMatch(phone)) return 'invalid_phone';
    if (province < 0 || province > 65535 || city < 0 || city > 65535) {
      return 'invalid_region';
    }
    if (!RegExp(r'^[A-Z0-9]{1,5}$').hasMatch(manufacturer) ||
        !RegExp(r'^[\x20-\x7E]{1,20}$').hasMatch(model) ||
        !RegExp(r'^[A-Z0-9]{1,7}$').hasMatch(terminalId)) {
      return 'invalid_identity';
    }
    if (plate.trim().isEmpty || ![0, 1, 2, 3, 4, 9].contains(plateColor)) {
      return 'invalid_plate';
    }
    if (heartbeatSeconds < 1 ||
        heartbeatSeconds > 3600 ||
        locationIntervalSeconds < 1 ||
        locationIntervalSeconds > 3600) {
      return 'invalid_interval';
    }
    return null;
  }

  TerminalConfig withAuthCode(String value) =>
      TerminalConfig.fromJson({...toJson(), 'authCode': value});

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'phone': phone,
    'province': province,
    'city': city,
    'manufacturer': manufacturer,
    'model': model,
    'terminalId': terminalId,
    'plate': plate,
    'plateColor': plateColor,
    'authCode': authCode,
    'heartbeatSeconds': heartbeatSeconds,
    'locationIntervalSeconds': locationIntervalSeconds,
    'autoReconnect': autoReconnect,
  };

  factory TerminalConfig.fromJson(Map<String, Object?> json) => TerminalConfig(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'JT808-001',
    host: json['host'] as String? ?? '127.0.0.1',
    port: json['port'] as int? ?? 7100,
    phone: json['phone'] as String? ?? '013800138000',
    province: json['province'] as int? ?? 1,
    city: json['city'] as int? ?? 1,
    manufacturer: json['manufacturer'] as String? ?? 'CHINA',
    model: json['model'] as String? ?? 'FLUTTER-808',
    terminalId: json['terminalId'] as String? ?? '0000001',
    plate: json['plate'] as String? ?? 'TEST001',
    plateColor: json['plateColor'] as int? ?? 1,
    authCode: json['authCode'] as String? ?? '',
    heartbeatSeconds: json['heartbeatSeconds'] as int? ?? 30,
    locationIntervalSeconds: json['locationIntervalSeconds'] as int? ?? 5,
    autoReconnect: json['autoReconnect'] as bool? ?? false,
  );
}

class LocationFix {
  const LocationFix({
    this.latitude = 39.9042,
    this.longitude = 116.4074,
    this.speed = 0,
    this.altitude = 0,
    this.direction = 0,
    this.alarm = 0,
    this.status = 0x00040003,
    this.mileage = 0,
    this.recordedAt,
  });
  final double latitude, longitude, speed, mileage;
  final int altitude, direction, alarm, status;
  final DateTime? recordedAt;

  /// Hemisphere bits are derived from the coordinates, never independently set.
  int get effectiveStatus =>
      (status & ~0x0c) |
      (latitude.isNegative ? 1 << 2 : 0) |
      (longitude.isNegative ? 1 << 3 : 0);

  String? get validationKey {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return 'invalid_coordinates';
    }
    if (!speed.isFinite ||
        speed < 0 ||
        speed > 6553.5 ||
        altitude < 0 ||
        altitude > 65535 ||
        direction < 0 ||
        direction > 359) {
      return 'invalid_motion';
    }
    if (!mileage.isFinite ||
        mileage < 0 ||
        mileage > 429496729.5 ||
        alarm < 0 ||
        alarm > 0xffffffff ||
        status < 0 ||
        status > 0xffffffff) {
      return 'invalid_flags';
    }
    return null;
  }

  LocationFix copyWith({
    double? latitude,
    double? longitude,
    double? speed,
    int? altitude,
    int? direction,
    int? alarm,
    int? status,
    double? mileage,
    DateTime? recordedAt,
  }) => LocationFix(
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    speed: speed ?? this.speed,
    altitude: altitude ?? this.altitude,
    direction: direction ?? this.direction,
    alarm: alarm ?? this.alarm,
    status: status ?? this.status,
    mileage: mileage ?? this.mileage,
    recordedAt: recordedAt ?? this.recordedAt,
  );

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speed': speed,
    'altitude': altitude,
    'direction': direction,
  };
  factory LocationFix.fromJson(Map<String, Object?> json) => LocationFix(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    speed: (json['speed'] as num? ?? 40).toDouble(),
    altitude: json['altitude'] as int? ?? 0,
    direction: json['direction'] as int? ?? 0,
  );
}

class DriveRoute {
  DriveRoute({
    required this.id,
    required this.name,
    required List<LocationFix> points,
    this.coordinateSystem = 'WGS84',
    this.planning,
  }) : points = List.unmodifiable(points);
  final String id, name, coordinateSystem;
  final RoutePlanMetadata? planning;
  final List<LocationFix> points;
  double get distanceKm {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceBetween(points[i - 1], points[i]);
    }
    return total;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'coordinateSystem': coordinateSystem,
    if (planning != null) 'planning': planning!.toJson(),
    'points': points.map((p) => p.toJson()).toList(),
  };
  factory DriveRoute.fromJson(Map<String, Object?> json) => DriveRoute(
    id: json['id'] as String,
    name: json['name'] as String,
    coordinateSystem: json['coordinateSystem'] as String? ?? 'WGS84',
    planning: json['planning'] == null
        ? null
        : RoutePlanMetadata.fromJson(
            Map<String, Object?>.from(json['planning'] as Map),
          ),
    points: (json['points'] as List)
        .map((p) => LocationFix.fromJson(Map<String, Object?>.from(p as Map)))
        .toList(),
  );
}

class DriveTask {
  const DriveTask({
    required this.id,
    required this.name,
    required this.terminalId,
    required this.routeId,
    this.loop = false,
  });
  final String id, name, terminalId, routeId;
  final bool loop;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'terminalId': terminalId,
    'routeId': routeId,
    'loop': loop,
  };
  factory DriveTask.fromJson(Map<String, Object?> json) => DriveTask(
    id: json['id'] as String,
    name: json['name'] as String,
    terminalId: json['terminalId'] as String,
    routeId: json['routeId'] as String,
    loop: json['loop'] as bool? ?? false,
  );
}

class ProtocolLog {
  ProtocolLog({
    required this.terminalId,
    required this.direction,
    required this.message,
    this.messageId,
    this.sequence,
    this.hex = '',
    this.isError = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();
  final String terminalId, message, hex;
  final LogDirection direction;
  final int? messageId, sequence;
  final bool isError;
  final DateTime time;
  String get idHex => messageId == null
      ? '—'
      : '0x${messageId!.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

sealed class ClientEvent {
  const ClientEvent();
}

class ConnectionChanged extends ClientEvent {
  const ConnectionChanged(this.phase, [this.details = '']);
  final ConnectionPhase phase;
  final String details;
}

class LogEmitted extends ClientEvent {
  const LogEmitted(this.log);
  final ProtocolLog log;
}

class AuthenticationCodeReceived extends ClientEvent {
  const AuthenticationCodeReceived(this.code);
  final String code;
}

class ParametersChanged extends ClientEvent {
  const ParametersChanged(this.parameters);
  final Map<int, List<int>> parameters;
}

/// Great-circle distance in kilometres; coordinates are never converted silently.
double distanceBetween(LocationFix a, LocationFix b) {
  const radians = math.pi / 180;
  final lat = (b.latitude - a.latitude) * radians;
  final lon = (b.longitude - a.longitude) * radians;
  final h =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(a.latitude * radians) *
          math.cos(b.latitude * radians) *
          math.pow(math.sin(lon / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}
