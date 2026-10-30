import 'package:flutter_map/flutter_map.dart';

import '../../domain/basemap_settings.dart';
import 'baidu_crs.dart';

class BasemapSource {
  const BasemapSource(this.settings);
  final BasemapSettings settings;

  // Amap and Baidu require an operator-supplied, authorized tile endpoint.
  // Community URLs are not public API contracts; see docs/BASEMAPS.md.
  String get urlTemplate => settings.tileUrl;

  List<String> get urlTemplates => settings.configurationKey != null
      ? const []
      : [
          urlTemplate,
          if (settings.provider == BasemapProvider.tianditu)
            settings.tiandituUrl('cva'),
        ];

  List<String> get subdomains => switch (settings.provider) {
    BasemapProvider.tianditu => const ['0', '1', '2', '3', '4', '5', '6', '7'],
    BasemapProvider.amap => const ['1', '2', '3', '4'],
    BasemapProvider.baidu => const ['0', '1', '2', '3'],
    _ => const ['a', 'b', 'c'],
  };

  Crs get crs => settings.provider == BasemapProvider.baidu
      ? const BaiduCrs()
      : const Epsg3857();

  String get coordinates => switch (settings.provider) {
    BasemapProvider.tianditu || BasemapProvider.openStreetMap => 'WGS84',
    BasemapProvider.amap => 'GCJ-02',
    BasemapProvider.baidu => 'BD-09',
    BasemapProvider.custom => switch (settings.customCoordinates) {
      BasemapCoordinates.wgs84 => 'WGS84',
      BasemapCoordinates.gcj02 => 'GCJ-02',
    },
  };

  String? get attributionKey => switch (settings.provider) {
    BasemapProvider.tianditu => 'sim.tianditu_attribution',
    BasemapProvider.openStreetMap => 'sim.osm_attribution',
    BasemapProvider.amap => 'sim.amap_attribution',
    BasemapProvider.baidu => 'sim.baidu_attribution',
    BasemapProvider.custom => null,
  };

  Uri? get attributionUrl => switch (settings.provider) {
    BasemapProvider.tianditu => Uri.parse('https://www.tianditu.gov.cn/'),
    BasemapProvider.openStreetMap => Uri.parse(
      'https://www.openstreetmap.org/copyright',
    ),
    BasemapProvider.amap => Uri.parse('https://lbs.amap.com/'),
    BasemapProvider.baidu => Uri.parse('https://lbsyun.baidu.com/'),
    BasemapProvider.custom => null,
  };

  double get maxZoom => switch (settings.provider) {
    BasemapProvider.tianditu || BasemapProvider.amap => 18,
    _ => 19,
  };
}

class SimulatorTileProvider extends NetworkTileProvider {
  SimulatorTileProvider(this.provider)
    : super(
        headers: {
          'User-Agent':
              'JT808Simulator/1.0 (com.marks.flutter_jtt808_simulator)',
        },
      );
  final BasemapProvider provider;

  @override
  Map<String, String> generateReplacementMap(
    String urlTemplate,
    TileCoordinates coordinates,
    TileLayer options,
  ) {
    final values = super.generateReplacementMap(
      urlTemplate,
      coordinates,
      options,
    );
    if (provider == BasemapProvider.baidu) {
      // flutter_map pixels grow down from Baidu's equatorial origin. Baidu's
      // tile rows grow up, with row 0 immediately north of that origin.
      String encode(int coordinate) =>
          coordinate < 0 ? 'M${-coordinate}' : '$coordinate';
      values['x'] = encode(coordinates.x);
      values['y'] = encode(-coordinates.y - 1);
    }
    return values;
  }
}
