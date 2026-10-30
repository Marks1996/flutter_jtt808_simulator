import 'package:equatable/equatable.dart';

enum BasemapProvider { tianditu, openStreetMap, amap, baidu, custom }

enum BasemapCoordinates { wgs84, gcj02 }

class BasemapSettings extends Equatable {
  const BasemapSettings({
    this.enabled = true,
    this.provider = BasemapProvider.tianditu,
    this.tiandituKey = '',
    this.amapKey = '',
    this.baiduKey = '',
    this.osmUrl = '',
    this.amapUrl = '',
    this.baiduUrl = '',
    this.customUrl = '',
    this.customAttribution = '',
    this.customCoordinates = BasemapCoordinates.wgs84,
  });

  static const legacyOsmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  // The public imagery service was checked with real Beijing image tiles at
  // zooms 12, 14, 16 and 19. Access is still subject to Esri's service terms.
  static const publicImageryUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const publicImageryAttribution =
      'Source: Esri, Vantor, Earthstar Geographics, and the GIS User Community';
  static const publicImageryInfoUrl =
      'https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9';
  final bool enabled;
  final BasemapProvider provider;
  final String tiandituKey,
      amapKey,
      baiduKey,
      osmUrl,
      amapUrl,
      baiduUrl,
      customUrl,
      customAttribution;
  final BasemapCoordinates customCoordinates;

  String tiandituUrl(String layer) =>
      'https://t{s}.tianditu.gov.cn/${layer}_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=$layer&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=${Uri.encodeQueryComponent(tiandituKey)}';

  /// Editable, unexpanded template. Never copy a rendered Key into this field.
  String get tileTemplate => switch (provider) {
    BasemapProvider.tianditu => tiandituUrl('vec'),
    BasemapProvider.openStreetMap => osmUrl,
    BasemapProvider.amap => amapUrl,
    BasemapProvider.baidu => baiduUrl,
    BasemapProvider.custom => customUrl,
  };

  bool get supportsKeyPlaceholder =>
      provider == BasemapProvider.amap || provider == BasemapProvider.baidu;

  String get providerKey => switch (provider) {
    BasemapProvider.tianditu => tiandituKey,
    BasemapProvider.amap => amapKey,
    BasemapProvider.baidu => baiduKey,
    _ => '',
  };

  String get tileUrl => supportsKeyPlaceholder
      ? tileTemplate.replaceAll('{key}', Uri.encodeQueryComponent(providerKey))
      : tileTemplate;

  BasemapSettings copyWith({
    bool? enabled,
    BasemapProvider? provider,
    String? tiandituKey,
    String? amapKey,
    String? baiduKey,
    String? osmUrl,
    String? amapUrl,
    String? baiduUrl,
    String? customUrl,
    String? customAttribution,
    BasemapCoordinates? customCoordinates,
  }) => BasemapSettings(
    enabled: enabled ?? this.enabled,
    provider: provider ?? this.provider,
    tiandituKey: tiandituKey ?? this.tiandituKey,
    amapKey: amapKey ?? this.amapKey,
    baiduKey: baiduKey ?? this.baiduKey,
    osmUrl: osmUrl ?? this.osmUrl,
    amapUrl: amapUrl ?? this.amapUrl,
    baiduUrl: baiduUrl ?? this.baiduUrl,
    customUrl: customUrl ?? this.customUrl,
    customAttribution: customAttribution ?? this.customAttribution,
    customCoordinates: customCoordinates ?? this.customCoordinates,
  );

  static String? validateTiandituKey(String value) =>
      value.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)
      ? 'invalid_tianditu_key'
      : null;

  static String? validateProviderKey(String value) =>
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)
      ? 'invalid_basemap_key'
      : null;

  static String? validateUrl(String value, {bool allowKey = false}) {
    if (!['{z}', '{x}', '{y}'].every(value.contains) ||
        RegExp(r'\s').hasMatch(value)) {
      return 'invalid_basemap_url';
    }
    final placeholders = RegExp(r'\{([^{}]*)\}');
    final allowed = ['x', 'y', 'z', 's', 'r', if (allowKey) 'key'];
    if (placeholders
        .allMatches(value)
        .any((match) => !allowed.contains(match.group(1)))) {
      return 'invalid_basemap_url';
    }
    // Keys may only be substituted in the query, never in a host or path.
    if (value.contains('{key}')) {
      final query = value.indexOf('?');
      if (query < 0 || value.indexOf('{key}') < query) {
        return 'invalid_basemap_url';
      }
    }
    final expanded = value.replaceAllMapped(placeholders, (_) => '1');
    final uri = Uri.tryParse(expanded);
    if (expanded.contains('{') ||
        expanded.contains('}') ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return 'invalid_basemap_url';
    }
    return null;
  }

  /// Missing values are a legitimate saved setup state. Nonempty malformed
  /// values are rejected; configurationKey separately gates tile requests.
  String? get validationKey {
    if (provider == BasemapProvider.tianditu) {
      return validateTiandituKey(tiandituKey);
    }
    if (supportsKeyPlaceholder && validateProviderKey(providerKey) != null) {
      return 'invalid_basemap_key';
    }
    if (tileTemplate.isEmpty) return null;
    return validateUrl(tileTemplate, allowKey: supportsKeyPlaceholder) ??
        (provider == BasemapProvider.custom && customAttribution.trim().isEmpty
            ? 'basemap_attribution_required'
            : null);
  }

  String? get configurationKey {
    if (validationKey case final error?) return error;
    if (provider == BasemapProvider.tianditu) {
      return tiandituKey.isEmpty ? 'tianditu_key_required' : null;
    }
    if (tileTemplate.isEmpty) return 'basemap_endpoint_required';
    if (supportsKeyPlaceholder &&
        tileTemplate.contains('{key}') &&
        providerKey.isEmpty) {
      return 'basemap_key_required';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'provider': provider.name,
    'tiandituKey': tiandituKey,
    'amapKey': amapKey,
    'baiduKey': baiduKey,
    'osmUrl': osmUrl,
    'amapUrl': amapUrl,
    'baiduUrl': baiduUrl,
    'customUrl': customUrl,
    'customAttribution': customAttribution,
    'customCoordinates': customCoordinates.name,
  };

  factory BasemapSettings.fromJson(Map<String, Object?> json) {
    final provider = BasemapProvider.values
        .where((value) => value.name == json['provider'])
        .firstOrNull;
    final coordinates = BasemapCoordinates.values
        .where((value) => value.name == json['customCoordinates'])
        .firstOrNull;
    if (provider == null ||
        (json['customCoordinates'] != null && coordinates == null)) {
      throw const FormatException('invalid_basemap');
    }
    final settings = BasemapSettings(
      enabled: json['enabled'] as bool? ?? true,
      provider: provider,
      tiandituKey: json['tiandituKey'] as String? ?? '',
      amapKey: json['amapKey'] as String? ?? '',
      baiduKey: json['baiduKey'] as String? ?? '',
      // Only old explicit OSM selections without this field inherit the old
      // endpoint. New or deliberately cleared connections remain empty.
      osmUrl: json.containsKey('osmUrl')
          ? json['osmUrl'] as String? ?? ''
          : provider == BasemapProvider.openStreetMap
          ? legacyOsmUrl
          : '',
      amapUrl: json['amapUrl'] as String? ?? '',
      baiduUrl: json['baiduUrl'] as String? ?? '',
      customUrl: json['customUrl'] as String? ?? '',
      customAttribution: json['customAttribution'] as String? ?? '',
      customCoordinates: coordinates ?? BasemapCoordinates.wgs84,
    );
    if (settings.validationKey case final key?) throw FormatException(key);
    return settings;
  }

  @override
  List<Object?> get props => [
    enabled,
    provider,
    tiandituKey,
    amapKey,
    baiduKey,
    osmUrl,
    amapUrl,
    baiduUrl,
    customUrl,
    customAttribution,
    customCoordinates,
  ];
}
