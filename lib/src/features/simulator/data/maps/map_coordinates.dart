import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/basemap_settings.dart';

/// Boundary conversion for map display, map selections and routing APIs.
/// Domain routes, playback, exports and JT808 reports always retain WGS84.
/// These local approximations are not survey-grade.
LatLng basemapCoordinates(LatLng wgs84, BasemapSettings settings) =>
    switch (settings.provider) {
      BasemapProvider.tianditu || BasemapProvider.openStreetMap => wgs84,
      BasemapProvider.amap => wgs84ToGcj02(wgs84),
      BasemapProvider.baidu =>
        _withinGcj02Bounds(wgs84) ? gcj02ToBd09(wgs84ToGcj02(wgs84)) : wgs84,
      BasemapProvider.custom => switch (settings.customCoordinates) {
        BasemapCoordinates.wgs84 => wgs84,
        BasemapCoordinates.gcj02 => wgs84ToGcj02(wgs84),
      },
    };

/// Approximate inverse for user-selected map points and routing responses.
/// Keep CSV imports explicit: these functions never reinterpret imported data.
LatLng basemapToWgs84(LatLng displayed, BasemapSettings settings) =>
    switch (settings.provider) {
      BasemapProvider.tianditu || BasemapProvider.openStreetMap => displayed,
      BasemapProvider.amap => gcj02ToWgs84(displayed),
      BasemapProvider.baidu =>
        _withinGcj02Bounds(displayed)
            ? gcj02ToWgs84(bd09ToGcj02(displayed))
            : displayed,
      BasemapProvider.custom => switch (settings.customCoordinates) {
        BasemapCoordinates.wgs84 => displayed,
        BasemapCoordinates.gcj02 => gcj02ToWgs84(displayed),
      },
    };

LatLng gcj02ToWgs84(LatLng point) {
  if (!_withinGcj02Bounds(point)) return point;
  var result = point;
  for (var i = 0; i < 8; i++) {
    final projected = wgs84ToGcj02(result);
    final latError = projected.latitude - point.latitude;
    final lonError = projected.longitude - point.longitude;
    result = LatLng(result.latitude - latError, result.longitude - lonError);
    if (latError.abs() + lonError.abs() < 1e-10) break;
  }
  return result;
}

LatLng bd09ToGcj02(LatLng point) {
  var result = LatLng(point.latitude - .006, point.longitude - .0065);
  for (var i = 0; i < 5; i++) {
    final projected = gcj02ToBd09(result);
    result = LatLng(
      result.latitude - (projected.latitude - point.latitude),
      result.longitude - (projected.longitude - point.longitude),
    );
  }
  return result;
}

// Conventional approximate conversion bounds, not a country-boundary test.
// Near borders, verify alignment against the operator's authorized source.
bool _withinGcj02Bounds(LatLng point) =>
    point.longitude >= 72.004 &&
    point.longitude <= 137.8347 &&
    point.latitude >= .8293 &&
    point.latitude <= 55.8271;

LatLng wgs84ToGcj02(LatLng point) {
  final lat = point.latitude, lon = point.longitude;
  if (!_withinGcj02Bounds(point)) return point;
  final x = lon - 105, y = lat - 35;
  final common =
      (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) * 2 / 3;
  final latitudeOffset =
      -100 +
      2 * x +
      3 * y +
      .2 * y * y +
      .1 * x * y +
      .2 * math.sqrt(x.abs()) +
      common +
      (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3 +
      (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
          2 /
          3;
  final longitudeOffset =
      300 +
      x +
      2 * y +
      .1 * x * x +
      .1 * x * y +
      .1 * math.sqrt(x.abs()) +
      common +
      (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3 +
      (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
          2 /
          3;
  const axis = 6378245.0, eccentricity = .006693421622965943;
  final radLat = lat * math.pi / 180;
  final sinLat = math.sin(radLat);
  final magic = 1 - eccentricity * sinLat * sinLat;
  final root = math.sqrt(magic);
  return LatLng(
    lat +
        latitudeOffset *
            180 /
            ((axis * (1 - eccentricity)) / (magic * root) * math.pi),
    lon + longitudeOffset * 180 / (axis / root * math.cos(radLat) * math.pi),
  );
}

LatLng gcj02ToBd09(LatLng point) {
  const factor = math.pi * 3000 / 180;
  final x = point.longitude, y = point.latitude;
  final radius = math.sqrt(x * x + y * y) + .00002 * math.sin(y * factor);
  final angle = math.atan2(y, x) + .000003 * math.cos(x * factor);
  return LatLng(
    radius * math.sin(angle) + .006,
    radius * math.cos(angle) + .0065,
  );
}
