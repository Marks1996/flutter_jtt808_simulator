import 'dart:math' as math;
import 'simulator_models.dart';

/// Advances along an explicit WGS84 polyline by elapsed time and segment speed.
/// This is trajectory playback, not a routing or coordinate conversion service.
class RoutePlayer {
  RoutePlayer(this.route, {this.loop = false}) {
    if (route.points.length < 2 ||
        route.coordinateSystem != 'WGS84' ||
        route.points.any((p) => p.validationKey != null || p.speed <= 0)) {
      throw const FormatException(
        'Route needs at least two valid WGS84 points with positive speed.',
      );
    }
  }
  final DriveRoute route;
  final bool loop;
  int _segment = 0;
  double _alongKm = 0;
  double _travelledKm = 0;
  bool finished = false;
  double get travelledKm => _travelledKm;
  double get progress => finished
      ? 1
      : route.distanceKm == 0
      ? 0
      : (_travelledKm % route.distanceKm) / route.distanceKm;
  LocationFix get current {
    if (finished) {
      return route.points.last.copyWith(speed: 0, mileage: _travelledKm);
    }
    final a = route.points[_segment];
    final b = route.points[_segment + 1];
    final distance = distanceBetween(a, b);
    final fraction = distance == 0
        ? 0.0
        : (_alongKm / distance).clamp(0.0, 1.0);
    const rad = math.pi / 180;
    final dLon = (b.longitude - a.longitude) * rad;
    final heading = math.atan2(
      math.sin(dLon) * math.cos(b.latitude * rad),
      math.cos(a.latitude * rad) * math.sin(b.latitude * rad) -
          math.sin(a.latitude * rad) *
              math.cos(b.latitude * rad) *
              math.cos(dLon),
    );
    final angular = distance / 6371;
    final from = angular == 0
        ? 1.0
        : math.sin((1 - fraction) * angular) / math.sin(angular);
    final to = angular == 0
        ? 0.0
        : math.sin(fraction * angular) / math.sin(angular);
    final x =
        from * math.cos(a.latitude * rad) * math.cos(a.longitude * rad) +
        to * math.cos(b.latitude * rad) * math.cos(b.longitude * rad);
    final y =
        from * math.cos(a.latitude * rad) * math.sin(a.longitude * rad) +
        to * math.cos(b.latitude * rad) * math.sin(b.longitude * rad);
    final z =
        from * math.sin(a.latitude * rad) + to * math.sin(b.latitude * rad);
    return a.copyWith(
      latitude: math.atan2(z, math.sqrt(x * x + y * y)) / rad,
      longitude: math.atan2(y, x) / rad,
      direction: ((heading / rad + 360) % 360).round() % 360,
      mileage: _travelledKm,
    );
  }

  LocationFix advance(Duration elapsed) {
    var seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // Guard degenerate loops: coincident points must not spin forever.
    final distance = route.distanceKm;
    if (distance < 0.000001) {
      finished = true;
      return current;
    }
    // Skip whole laps, keeping large time steps bounded even for very short routes.
    if (loop && _segment == 0 && _alongKm == 0) {
      var lapSeconds = 0.0;
      for (var i = 0; i < route.points.length - 1; i++) {
        lapSeconds +=
            distanceBetween(route.points[i], route.points[i + 1]) /
            route.points[i].speed *
            3600;
      }
      final laps = (seconds / lapSeconds).floor();
      _travelledKm += laps * distance;
      seconds -= laps * lapSeconds;
    }
    while (seconds > 0 && !finished) {
      final a = route.points[_segment];
      final remaining =
          distanceBetween(a, route.points[_segment + 1]) - _alongKm;
      final available = a.speed * seconds / 3600;
      if (available < remaining) {
        _alongKm += available;
        _travelledKm += available;
        break;
      }
      seconds -= remaining / a.speed * 3600;
      _travelledKm += remaining;
      _alongKm = 0;
      if (_segment + 2 < route.points.length) {
        _segment++;
      } else if (loop) {
        _segment = 0;
      } else {
        finished = true;
      }
    }
    return current;
  }
}

/// The interchange format deliberately has an explicit coordinate system.
abstract final class RouteCsv {
  static DriveRoute parse(
    String text, {
    required String id,
    required String name,
  }) {
    final lines = text
        .trim()
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first.trim().toUpperCase() != '# WGS84') {
      throw const FormatException('route_coordinate_header');
    }
    final data = lines.skip(1).toList();
    if (data.isNotEmpty && data.first.toLowerCase().startsWith('latitude,')) {
      data.removeAt(0);
    }
    if (data.length < 2 || data.length > 10000) {
      throw const FormatException('route_point_count');
    }
    final points = <LocationFix>[];
    for (final line in data) {
      final columns = line.split(',').map((e) => e.trim()).toList();
      if (columns.length != 3) throw const FormatException('route_csv_invalid');
      final values = columns.map(double.tryParse).toList();
      if (values.any((v) => v == null || !v.isFinite)) {
        throw const FormatException('route_csv_invalid');
      }
      final p = LocationFix(
        latitude: values[0]!,
        longitude: values[1]!,
        speed: values[2]!,
      );
      if (p.validationKey != null || p.speed <= 0 || p.speed > 200) {
        throw const FormatException('route_csv_invalid');
      }
      points.add(p);
    }
    if (name.trim().isEmpty) throw const FormatException('required');
    final route = DriveRoute(id: id, name: name.trim(), points: points);
    if (route.distanceKm < 0.000001) {
      throw const FormatException('route_zero_length');
    }
    return route;
  }

  static String encode(DriveRoute route) =>
      '# WGS84\nlatitude,longitude,speed\n${route.points.map((p) => '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)},${p.speed}').join('\n')}';

  /// Illustrative coordinates only: never labelled as a planned road route.
  static const example =
      '# WGS84\nlatitude,longitude,speed\n39.904200,116.407400,40\n39.906200,116.407400,30\n39.906200,116.411400,40\n39.904200,116.411400,30\n39.904200,116.407400,40';
}
