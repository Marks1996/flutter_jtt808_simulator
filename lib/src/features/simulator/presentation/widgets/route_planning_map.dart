import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/maps/basemap_source.dart';
import '../../data/maps/map_coordinates.dart';
import '../providers/simulator_provider.dart';
import 'basemap_tile_layer.dart';
import 'sim_ui.dart';

class RoutePlanningMap extends ConsumerStatefulWidget {
  const RoutePlanningMap({
    super.key,
    required this.waypoints,
    required this.onPicked,
    required this.onSelected,
    this.selected,
    this.geometry = const [],
    this.enabled = true,
    this.canPick = true,
  });
  final List<RouteWaypoint> waypoints, geometry;
  final ValueChanged<RouteWaypoint> onPicked;
  final ValueChanged<int> onSelected;
  final int? selected;
  final bool enabled, canPick;

  @override
  ConsumerState<RoutePlanningMap> createState() => _RoutePlanningMapState();
}

class _RoutePlanningMapState extends ConsumerState<RoutePlanningMap> {
  int _attempt = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(simulatorProvider.select((c) => c.workspace.basemap), (
      _,
      _,
    ) {
      setState(() {
        _attempt++;
        _failed = false;
      });
    });
  }

  void _fallback(int attempt) {
    if (!mounted || _failed || attempt != _attempt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failed && attempt == _attempt) {
        setState(() => _failed = true);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(
      simulatorProvider.select((c) => c.workspace.basemap),
    );
    final online = saved.enabled && saved.configurationKey == null && !_failed;
    final source = BasemapSource(
      online ? saved : const BasemapSettings(enabled: false),
    );
    LatLng project(RouteWaypoint point) => basemapCoordinates(
      LatLng(point.latitude, point.longitude),
      source.settings,
    );
    final points = widget.waypoints.map(project).toList();
    final attempt = _attempt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (saved.enabled && saved.configurationKey != null) ...[
          SimNotice(
            key: const ValueKey('planning-basemap-setup-required'),
            text: tr('sim.errors.${saved.configurationKey}'),
          ),
          SizedBox(height: SimSpace.ms),
        ],
        ClipRRect(
          borderRadius: AppBorders.input,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).width < 600 ? 280 : 340,
            child: FlutterMap(
              key: ValueKey(('route-planning-map', source.settings, attempt)),
              options: MapOptions(
                crs: source.crs,
                backgroundColor: context.colors.surfaceContainerLow,
                minZoom: 3,
                maxZoom: source.maxZoom,
                initialCenter:
                    points.firstOrNull ?? const LatLng(39.9042, 116.4074),
                initialZoom: 12,
                initialCameraFit: points.toSet().length < 2
                    ? null
                    : CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(points),
                        padding: EdgeInsets.all(SimSpace.xl * 3),
                        maxZoom: 15,
                      ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: widget.enabled && widget.canPick
                    ? (_, point) {
                        final wgs = basemapToWgs84(point, source.settings);
                        widget.onPicked(
                          RouteWaypoint(wgs.latitude, wgs.longitude),
                        );
                      }
                    : null,
              ),
              children: [
                if (online)
                  BasemapTileLayer(
                    source: source,
                    onError: () => _fallback(attempt),
                  ),
                if (widget.geometry.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.geometry.map(project).toList(),
                        color: context.colors.primary,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < points.length; i++)
                      Marker(
                        point: points[i],
                        width: 36,
                        height: 36,
                        child: ShadButton(
                          key: ValueKey('waypoint-marker-$i'),
                          width: 36,
                          height: 36,
                          padding: EdgeInsets.zero,
                          backgroundColor: widget.selected == i
                              ? context.colors.primary
                              : context.colors.surface,
                          foregroundColor: widget.selected == i
                              ? context.colors.onPrimary
                              : context.colors.primary,
                          enabled: widget.enabled,
                          onPressed: () => widget.onSelected(i),
                          child: Text(
                            '${i + 1}',
                            semanticsLabel: tr(
                              'sim.routing.point_number',
                              namedArgs: {'number': '${i + 1}'},
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: EdgeInsets.all(SimSpace.ms),
                    child: Builder(
                      builder: (context) => ShadIconButton.outline(
                        icon: Icon(
                          Icons.fit_screen,
                          size: 18,
                          semanticLabel: tr('sim.routing.fit_points'),
                        ),
                        onPressed: points.isEmpty
                            ? null
                            : () {
                                final map = MapController.of(context);
                                if (points.toSet().length < 2) {
                                  map.move(points.first, 14);
                                } else {
                                  map.fitCamera(
                                    CameraFit.bounds(
                                      bounds: LatLngBounds.fromPoints(points),
                                      padding: EdgeInsets.all(SimSpace.xl * 3),
                                      maxZoom: 16,
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: SimSpace.sm),
        if (online)
          if (source.attributionUrl case final url?)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.link(
                expands: true,
                mainAxisAlignment: MainAxisAlignment.start,
                height: 0,
                padding: EdgeInsets.zero,
                onPressed: () => simRun(context, () async {
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('Unable to open attribution');
                  }
                }),
                child: Text(
                  tr(source.attributionKey!),
                  style: context.textTheme.bodySmall,
                ),
              ),
            )
          else
            Text(saved.customAttribution, style: context.textTheme.bodySmall)
        else
          Text(tr('sim.routing.no_tiles'), style: context.textTheme.bodySmall),
        if (_failed)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => setState(() {
                _attempt++;
                _failed = false;
              }),
              child: Text(tr('sim.retry_basemap')),
            ),
          ),
      ],
    );
  }
}
