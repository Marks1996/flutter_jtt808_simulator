import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../data/maps/basemap_source.dart';
import '../../domain/basemap_settings.dart';

/// TileLayer owns each provider. A source/retry recreates the parent map and
/// these layers together. Tianditu uses independent base and label providers.
class BasemapTileLayer extends StatefulWidget {
  const BasemapTileLayer({
    super.key,
    required this.source,
    required this.onError,
  });
  final BasemapSource source;
  final VoidCallback onError;
  @override
  State<BasemapTileLayer> createState() => _BasemapTileLayerState();
}

class _BasemapTileLayerState extends State<BasemapTileLayer> {
  late final _urls = widget.source.urlTemplates;
  late final _providers = [
    for (final _ in _urls)
      SimulatorTileProvider(widget.source.settings.provider),
  ];

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < _urls.length; i++)
        TileLayer(
          key: ValueKey(i),
          urlTemplate: _urls[i],
          subdomains: widget.source.subdomains,
          minNativeZoom:
              widget.source.settings.provider == BasemapProvider.baidu ? 3 : 0,
          maxNativeZoom: widget.source.maxZoom.toInt(),
          tileProvider: _providers[i],
          userAgentPackageName: 'com.marks.flutter_jtt808_simulator',
          errorTileCallback: (tile, error, stack) => widget.onError(),
        ),
    ],
  );
}
