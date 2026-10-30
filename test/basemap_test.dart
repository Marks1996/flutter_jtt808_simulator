import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_jtt808_simulator/src/features/simulator/data/maps/baidu_crs.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/maps/basemap_source.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/maps/map_coordinates.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/domain/simulator_repository.dart';

const _url = 'https://tiles.example.com/{z}/{x}/{y}.png?token=local-test';

void main() {
  group('basemap settings', () {
    test(
      'new and legacy workspaces enable domestic Tianditu pending Key setup',
      () {
        final fresh = SimulatorWorkspace();
        expect(fresh.basemap.enabled, isTrue);
        expect(fresh.basemap.provider, BasemapProvider.tianditu);
        expect(fresh.basemap.tiandituKey, isEmpty);
        expect(fresh.basemap.validationKey, isNull);
        expect(fresh.basemap.configurationKey, 'tianditu_key_required');
        final old = fresh.toJson()..remove('basemap');
        expect(SimulatorWorkspace.fromJson(old).basemap, fresh.basemap);
        expect(fresh.copyWith(theme: 'dark').basemap, fresh.basemap);
      },
    );

    test('tested imagery preset uses ArcGIS row-column order and WGS84', () {
      const settings = BasemapSettings(
        provider: BasemapProvider.custom,
        customUrl: BasemapSettings.publicImageryUrl,
        customAttribution: BasemapSettings.publicImageryAttribution,
      );
      expect(settings.configurationKey, isNull);
      expect(BasemapSettings.fromJson(settings.toJson()), settings);
      expect(const BasemapSource(settings).coordinates, 'WGS84');
      const point = LatLng(39.9042, 116.4074);
      expect(basemapCoordinates(point, settings), point);
      final provider = SimulatorTileProvider(BasemapProvider.custom);
      addTearDown(provider.dispose);
      final url = provider.getTileUrl(
        const TileCoordinates(13489, 6208, 14),
        TileLayer(urlTemplate: settings.tileUrl),
      );
      expect(
        url,
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/14/6208/13489',
      );
      expect(url, isNot(contains('key=')));
      expect(settings.customAttribution, contains('Esri'));
      expect(settings.customAttribution, contains('Vantor'));
      expect(settings.customAttribution, contains('Earthstar Geographics'));
    });

    test('each provider preserves its own endpoint through workspace JSON', () {
      for (final provider in BasemapProvider.values) {
        final settings = BasemapSettings(
          enabled: false,
          provider: provider,
          tiandituKey: 'test-tianditu-key',
          amapKey: 'test-amap-key',
          baiduKey: 'test-baidu-key',
          osmUrl: '$_url&source=osm',
          amapUrl: '$_url&source=amap',
          baiduUrl: '$_url&source=baidu',
          customUrl: _url,
          customAttribution: '© Test source',
          customCoordinates: BasemapCoordinates.gcj02,
        );
        final workspace = SimulatorWorkspace(basemap: settings);
        expect(
          SimulatorWorkspace.fromJson(workspace.toJson()).basemap,
          settings,
        );
        expect(settings.copyWith(enabled: true).provider, provider);
      }
    });

    test(
      'Tianditu uses official vector and labels WMTS layers with own Key',
      () {
        const settings = BasemapSettings(tiandituKey: 'test-Key_123');
        const source = BasemapSource(settings);
        expect(source.urlTemplates, [
          settings.tiandituUrl('vec'),
          settings.tiandituUrl('cva'),
        ]);
        for (final layer in ['vec', 'cva']) {
          final template = settings.tiandituUrl(layer);
          expect(
            template,
            startsWith('https://t{s}.tianditu.gov.cn/${layer}_w/wmts?'),
          );
          final uri = Uri.parse(
            template
                .replaceAll('{s}', '0')
                .replaceAll('{z}', '12')
                .replaceAll('{x}', '790')
                .replaceAll('{y}', '294'),
          );
          expect(uri.queryParameters, containsPair('SERVICE', 'WMTS'));
          expect(uri.queryParameters, containsPair('REQUEST', 'GetTile'));
          expect(uri.queryParameters, containsPair('LAYER', layer));
          expect(uri.queryParameters, containsPair('TILEMATRIXSET', 'w'));
          expect(uri.queryParameters, containsPair('TILEMATRIX', '12'));
          expect(uri.queryParameters, containsPair('TILEROW', '294'));
          expect(uri.queryParameters, containsPair('TILECOL', '790'));
          expect(uri.queryParameters, containsPair('tk', settings.tiandituKey));
        }
        expect(source.subdomains, ['0', '1', '2', '3', '4', '5', '6', '7']);
        expect(source.maxZoom, 18);
        expect(source.coordinates, 'WGS84');
        expect(source.crs, isA<Epsg3857>());
        expect(source.attributionUrl!.host, 'www.tianditu.gov.cn');
        expect(settings.configurationKey, isNull);
        expect(
          settings
              .copyWith(provider: BasemapProvider.openStreetMap)
              .copyWith(provider: BasemapProvider.tianditu)
              .tiandituKey,
          settings.tiandituKey,
        );
      },
    );

    test(
      'empty Tianditu Key persists but creates no usable source; malformed Keys fail',
      () {
        const settings = BasemapSettings();
        expect(BasemapSettings.fromJson(settings.toJson()), settings);
        expect(const BasemapSource(settings).urlTemplates, isEmpty);
        for (final key in ['bad key', 'key&other=value', '{key}', 'key/part']) {
          final invalid = settings.copyWith(tiandituKey: key);
          expect(invalid.validationKey, 'invalid_tianditu_key');
          expect(invalid.configurationKey, 'invalid_tianditu_key');
          expect(BasemapSource(invalid).urlTemplates, isEmpty);
          expect(
            () => BasemapSettings.fromJson(invalid.toJson()),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'missing endpoints persist as setup states without usable sources',
      () {
        for (final provider in BasemapProvider.values.where(
          (provider) => provider != BasemapProvider.tianditu,
        )) {
          final settings = BasemapSettings(provider: provider);
          expect(settings.validationKey, isNull);
          expect(settings.configurationKey, 'basemap_endpoint_required');
          expect(BasemapSettings.fromJson(settings.toJson()), settings);
          expect(BasemapSource(settings).urlTemplates, isEmpty);
        }
      },
    );

    test(
      'OSM migrates only missing legacy fields and preserves cleared URLs',
      () {
        const fresh = BasemapSettings(provider: BasemapProvider.openStreetMap);
        expect(fresh.osmUrl, isEmpty);
        expect(fresh.providerKey, isEmpty);
        expect(fresh.supportsKeyPlaceholder, isFalse);
        final legacy = fresh.toJson()..remove('osmUrl');
        final migrated = BasemapSettings.fromJson(legacy);
        expect(migrated.osmUrl, BasemapSettings.legacyOsmUrl);
        expect(BasemapSource(migrated).urlTemplates, [
          BasemapSettings.legacyOsmUrl,
        ]);
        for (final value in ['', null]) {
          final restored = BasemapSettings.fromJson({
            ...legacy,
            'osmUrl': value,
          });
          expect(restored.osmUrl, isEmpty);
          expect(restored.configurationKey, 'basemap_endpoint_required');
        }
        final custom = fresh.copyWith(osmUrl: _url);
        expect(BasemapSettings.fromJson(custom.toJson()), custom);
        expect(BasemapSource(custom).urlTemplates, [_url]);
        final cleared = BasemapSettings.fromJson(
          custom.copyWith(osmUrl: '').toJson(),
        );
        expect(cleared.osmUrl, isEmpty);
        expect(BasemapSource(cleared).urlTemplates, isEmpty);
        expect(
          BasemapSettings.fromJson({...legacy, 'provider': 'amap'}).osmUrl,
          isEmpty,
        );
      },
    );

    test(
      'independent Keys copy, clear and persist without changing routing',
      () {
        final workspace = SimulatorWorkspace(
          basemap: const BasemapSettings(
            tiandituKey: 'tianditu',
            amapKey: 'tiles-amap',
            baiduKey: 'baidu',
          ),
          routing: const RoutePlanningSettings(amapKey: 'routing-amap'),
        );
        final original = workspace.basemap;
        for (final provider in [
          BasemapProvider.tianditu,
          BasemapProvider.amap,
          BasemapProvider.baidu,
        ]) {
          final selected = original.copyWith(provider: provider);
          expect(selected.providerKey, switch (provider) {
            BasemapProvider.tianditu => 'tianditu',
            BasemapProvider.amap => 'tiles-amap',
            _ => 'baidu',
          });
          expect(BasemapSettings.fromJson(selected.toJson()), selected);
        }
        for (final changed in [
          original.copyWith(tiandituKey: ''),
          original.copyWith(amapKey: ''),
          original.copyWith(baiduKey: ''),
        ]) {
          expect(changed, isNot(original));
          expect(BasemapSettings.fromJson(changed.toJson()), changed);
          final restored = SimulatorWorkspace.fromJson(
            workspace.copyWith(basemap: changed).toJson(),
          );
          expect(restored.routing.amapKey, 'routing-amap');
        }
        expect(original.copyWith(amapKey: '').baiduKey, 'baidu');
        expect(original.copyWith(baiduKey: '').amapKey, 'tiles-amap');
      },
    );

    test('provider Keys are optional but reject whitespace and controls', () {
      expect(BasemapSettings.validateProviderKey(''), isNull);
      expect(BasemapSettings.validateProviderKey('a&b=中+%?#/{}'), isNull);
      for (final key in [
        'bad key',
        'bad\tkey',
        'bad\nkey',
        'bad\u0000key',
        'bad\u007fkey',
      ]) {
        expect(BasemapSettings.validateProviderKey(key), 'invalid_basemap_key');
        for (final provider in [BasemapProvider.amap, BasemapProvider.baidu]) {
          final settings = BasemapSettings(
            provider: provider,
            amapKey: key,
            baiduKey: key,
          );
          expect(settings.validationKey, 'invalid_basemap_key');
          expect(
            () => BasemapSettings.fromJson(settings.toJson()),
            throwsFormatException,
          );
        }
      }
    });

    test(
      'Key placeholders are restricted to authorized provider query templates',
      () {
        const template =
            'https://tiles.example.com/{z}/{x}/{y}.png?key={key}&copy={key}';
        expect(BasemapSettings.validateUrl(template), 'invalid_basemap_url');
        expect(BasemapSettings.validateUrl(template, allowKey: true), isNull);
        for (final url in [
          'https://{key}.example.com/{z}/{x}/{y}.png',
          'https://tiles.example.com/{key}/{z}/{x}/{y}.png?key={key}',
          'https://tiles.example.com/{z}/{x}/{y}.png?key={unknown}',
          '$template#fragment',
        ]) {
          expect(
            BasemapSettings.validateUrl(url, allowKey: true),
            'invalid_basemap_url',
            reason: url,
          );
        }
        for (final provider in [
          BasemapProvider.openStreetMap,
          BasemapProvider.custom,
        ]) {
          final settings = BasemapSettings(
            provider: provider,
            osmUrl: template,
            customUrl: template,
            customAttribution: 'Source',
          );
          expect(settings.supportsKeyPlaceholder, isFalse);
          expect(settings.validationKey, 'invalid_basemap_url');
        }
        const key = 'a&b=中+%?#/{}';
        for (final provider in [BasemapProvider.amap, BasemapProvider.baidu]) {
          final pending = BasemapSettings(
            provider: provider,
            amapUrl: template,
            baiduUrl: template,
          );
          expect(pending.supportsKeyPlaceholder, isTrue);
          expect(pending.validationKey, isNull);
          expect(pending.configurationKey, 'basemap_key_required');
          expect(BasemapSource(pending).urlTemplates, isEmpty);
          final ready = pending.copyWith(
            amapKey: provider == BasemapProvider.amap ? key : 'other',
            baiduKey: provider == BasemapProvider.baidu ? key : 'other',
          );
          expect(ready.configurationKey, isNull);
          expect(ready.tileTemplate, template);
          expect(
            ready.tileUrl,
            template.replaceAll('{key}', Uri.encodeQueryComponent(key)),
          );
          final uri = Uri.parse(ready.tileUrl);
          expect(uri.queryParameters, {'key': key, 'copy': key});
          expect(BasemapSource(ready).urlTemplates, [ready.tileUrl]);
          expect(
            ready.toJson()[provider == BasemapProvider.amap
                ? 'amapUrl'
                : 'baiduUrl'],
            template,
          );
          expect(BasemapSettings.fromJson(ready.toJson()), ready);
          final onlyKey = ready.copyWith(amapUrl: '', baiduUrl: '');
          expect(onlyKey.validationKey, isNull);
          expect(onlyKey.configurationKey, 'basemap_endpoint_required');
          expect(BasemapSource(onlyKey).urlTemplates, isEmpty);
          expect(BasemapSettings.fromJson(onlyKey.toJson()), onlyKey);
          final authorized = pending.copyWith(amapUrl: _url, baiduUrl: _url);
          expect(authorized.configurationKey, isNull);
          expect(authorized.tileUrl, _url);
          expect(
            authorized.copyWith(amapKey: key, baiduKey: key).tileUrl,
            _url,
          );
        }
      },
    );

    test('validates templates and mandatory custom source attribution', () {
      expect(BasemapSettings.validateUrl(_url), isNull);
      expect(
        BasemapSettings.validateUrl(
          'https://{s}.example.com/{z}/{x}/{y}{r}.png',
        ),
        isNull,
      );
      for (final url in [
        '',
        'http://tiles.example.com/{z}/{x}/{y}.png',
        'https://tiles.example.com/{z}/{x}.png',
        'https://tiles.example.com/{z}/{x}/{y}.png?key={key}',
        'https://tiles.example.com/{z}/{x}/{y}.png#fragment',
        'https://user:password@tiles.example.com/{z}/{x}/{y}.png',
        'https://tiles.example.com/{z}/{x}/{y}.png extra',
        'https://tiles.example.com/{z}/{x}/{y}.png{',
      ]) {
        expect(
          BasemapSettings.validateUrl(url),
          'invalid_basemap_url',
          reason: url,
        );
      }
      expect(
        const BasemapSettings(
          provider: BasemapProvider.custom,
          customUrl: _url,
        ).validationKey,
        'basemap_attribution_required',
      );
    });

    test(
      'rejects unsupported coordinate systems and invalid persisted settings',
      () {
        final json = const BasemapSettings().toJson();
        for (final invalid in [
          {...json, 'provider': 'unknown'},
          {...json, 'customCoordinates': 'bd09'},
          {...json, 'provider': 'custom', 'customUrl': _url},
          {...json, 'provider': 'baidu', 'baiduUrl': 'http://bad/{z}/{x}/{y}'},
        ]) {
          expect(
            () => BasemapSettings.fromJson(invalid),
            throwsFormatException,
          );
        }
      },
    );
  });

  group('display-only coordinates', () {
    const point = LatLng(39.915, 116.404);
    test('matches published Beijing GCJ-02 and BD-09 conversion fixtures', () {
      final gcj = wgs84ToGcj02(point);
      expect(gcj.latitude, closeTo(39.91640428150164, 1e-9));
      expect(gcj.longitude, closeTo(116.41024449916938, 1e-9));
      final bd = gcj02ToBd09(gcj);
      expect(bd.latitude, closeTo(39.922699552216216, 1e-9));
      expect(bd.longitude, closeTo(116.41662724378733, 1e-9));
      expect(point, const LatLng(39.915, 116.404));
    });

    test(
      'selects provider conversion without mutating route or protocol data',
      () {
        expect(basemapCoordinates(point, const BasemapSettings()), point);
        expect(
          basemapCoordinates(
            point,
            const BasemapSettings(provider: BasemapProvider.amap),
          ),
          wgs84ToGcj02(point),
        );
        expect(
          basemapCoordinates(
            point,
            const BasemapSettings(provider: BasemapProvider.baidu),
          ),
          gcj02ToBd09(wgs84ToGcj02(point)),
        );
        expect(
          basemapCoordinates(
            point,
            const BasemapSettings(
              provider: BasemapProvider.custom,
              customCoordinates: BasemapCoordinates.gcj02,
            ),
          ),
          wgs84ToGcj02(point),
        );
        const foreign = LatLng(51.5074, -.1278);
        for (final provider in BasemapProvider.values) {
          expect(
            basemapCoordinates(foreign, BasemapSettings(provider: provider)),
            foreign,
          );
        }
      },
    );
  });

  group('Baidu projection and tiles', () {
    const crs = BaiduCrs();
    test('uses Baidu Mercator rather than standard Web Mercator', () {
      final (x, y) = crs.projection.projectXY(const LatLng(39.915, 116.404));
      expect(x, closeTo(12958175.000248697, .001));
      expect(y, closeTo(4825923.766034241, .001));
      expect(crs.scale(18), 1);
      expect(crs.scale(12), 1 / 64);
      expect(crs.zoom(crs.scale(12.5)), closeTo(12.5, 1e-10));
      expect(crs.infinite, isTrue);
      expect(crs.wrapLng, isNull);
    });

    test('round-trips every polynomial band in both hemispheres', () {
      for (final latitude in [
        0.0,
        14.9,
        15.0,
        29.9,
        30.0,
        44.9,
        45.0,
        59.9,
        60.0,
        73.9,
      ]) {
        for (final sign in [-1, 1]) {
          final point = LatLng(latitude * sign, 116.404 * sign);
          final offset = crs.latLngToOffset(point, 14);
          final restored = crs.offsetToLatLng(offset, 14);
          expect(restored.latitude, closeTo(point.latitude, .0001));
          expect(restored.longitude, closeTo(point.longitude, 1e-6));
        }
      }
    });

    test(
      'converts equatorial-origin rows and M-encodes negative Baidu indices',
      () {
        final provider = SimulatorTileProvider(BasemapProvider.baidu);
        addTearDown(provider.dispose);
        final options = TileLayer(urlTemplate: _url);
        final offset = crs.latLngToOffset(const LatLng(39.915, 116.404), 12);
        final tile = TileCoordinates(
          (offset.dx / 256).floor(),
          (offset.dy / 256).floor(),
          12,
        );
        expect(tile.x, 790);
        expect(tile.y, -295);
        expect(
          provider.getTileUrl(tile, options),
          'https://tiles.example.com/12/790/294.png?token=local-test',
        );
        expect(
          provider.getTileUrl(const TileCoordinates(-1, 0, 3), options),
          'https://tiles.example.com/3/M1/M1.png?token=local-test',
        );
        expect(
          provider.getTileUrl(const TileCoordinates(0, -1, 3), options),
          'https://tiles.example.com/3/0/0.png?token=local-test',
        );
      },
    );

    test('leaves standard XYZ numbering unchanged', () {
      for (final source in [
        BasemapProvider.tianditu,
        BasemapProvider.openStreetMap,
        BasemapProvider.amap,
        BasemapProvider.custom,
      ]) {
        final provider = SimulatorTileProvider(source);
        addTearDown(provider.dispose);
        final options = TileLayer(urlTemplate: _url);
        expect(
          provider.getTileUrl(const TileCoordinates(790, 294, 12), options),
          'https://tiles.example.com/12/790/294.png?token=local-test',
        );
      }
    });

    test('sources resolve their correct coordinate reference system', () {
      expect(const BasemapSource(BasemapSettings()).crs, isA<Epsg3857>());
      expect(
        const BasemapSource(
          BasemapSettings(provider: BasemapProvider.baidu),
        ).crs,
        isA<BaiduCrs>(),
      );
      expect(
        const BasemapSource(
          BasemapSettings(provider: BasemapProvider.amap, amapUrl: _url),
        ).urlTemplate,
        _url,
      );
      final (x, y) = crs.transform(10, 20, math.pow(2, -1).toDouble());
      expect((x, y), (5, -10));
    });
  });
}
