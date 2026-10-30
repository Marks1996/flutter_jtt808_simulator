import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../data/maps/basemap_source.dart';
import '../../data/maps/map_coordinates.dart';
import '../providers/simulator_provider.dart';
import 'basemap_tile_layer.dart';
import 'route_data_links.dart';
import 'sim_ui.dart';

/// Uses the saved basemap preference, with a temporary offline fallback.
/// Only display coordinates are converted; the supplied WGS84 data is immutable.
class RoutePreview extends ConsumerStatefulWidget {
  const RoutePreview({super.key, this.route, this.location, this.height = 270});
  final DriveRoute? route;
  final LocationFix? location;
  final double height;

  @override
  ConsumerState<RoutePreview> createState() => _RoutePreviewState();
}

class _RoutePreviewState extends ConsumerState<RoutePreview> {
  bool _tileFailed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      simulatorProvider.select((controller) => controller.workspace.basemap),
      (previous, next) => setState(() {
        _tileFailed = false;
        _attempt++;
      }),
    );
  }

  void _fallback(int attempt) {
    if (_tileFailed || !mounted || attempt != _attempt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed && attempt == _attempt) {
        setState(() => _tileFailed = true);
      }
    });
    // Tile errors can arrive while the scheduler is idle. A post-frame
    // callback alone would otherwise wait until the next user interaction.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(
      simulatorProvider.select((controller) => controller.workspace.basemap),
    );
    final source = BasemapSource(settings);
    final online =
        settings.enabled && settings.configurationKey == null && !_tileFailed;
    final points = [
      ...?widget.route?.points,
      if (widget.location != null) widget.location!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                online
                    ? tr(
                        'sim.map_online',
                        namedArgs: {
                          'provider': tr(
                            'sim.basemap_provider.${settings.provider.name}',
                          ),
                          'coordinates': source.coordinates,
                        },
                      )
                    : tr('sim.map_offline'),
                style: context.textTheme.labelMedium,
              ),
            ),
            SizedBox(width: SimSpace.ms),
            ShadTooltip(
              builder: (_) => Text(tr('sim.map_online_hint')),
              child: ShadSwitch(
                key: const ValueKey('preview-basemap-enabled'),
                value: settings.enabled,
                label: Text(
                  tr('sim.online_basemap'),
                  style: context.textTheme.bodySmall,
                ),
                onChanged: (value) => simRun(
                  context,
                  () => ref
                      .read(simulatorProvider)
                      .setBasemap(settings.copyWith(enabled: value)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: SimSpace.sm),
        if (settings.enabled && settings.configurationKey != null) ...[
          SimNotice(
            key: const ValueKey('basemap-setup-required'),
            text: tr('sim.errors.${settings.configurationKey}'),
          ),
          SizedBox(height: SimSpace.sm),
        ],
        ClipRRect(
          borderRadius: AppBorders.input,
          child: SizedBox(
            height: widget.height,
            child: points.isEmpty
                ? ColoredBox(
                    color: context.colors.surfaceContainerLow,
                    child: Center(
                      child: Text(
                        tr('sim.no_coordinates'),
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  )
                : online
                ? _tiles(context, points, source)
                : _plot(context, points),
          ),
        ),
        if (online && points.isNotEmpty) ...[
          SizedBox(height: SimSpace.sm),
          // Keep attribution visible, rather than behind an information toggle.
          if (source.attributionUrl case final url?)
            ShadButton.link(
              height: 0,
              expands: true,
              padding: EdgeInsets.zero,
              mainAxisAlignment: MainAxisAlignment.start,
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
            )
          else
            Text(
              settings.customAttribution,
              style: context.textTheme.bodySmall,
            ),
        ],
        if (widget.route?.planning case final origin?) ...[
          SizedBox(height: SimSpace.sm),
          Text(
            tr('sim.routing.attribution.${origin.provider.name}'),
            style: context.textTheme.bodySmall,
          ),
          if (origin.provider == RoutingProvider.osrm) const RouteDataLinks(),
        ],
        SizedBox(height: SimSpace.sm),
        Text(
          tr('sim.map_disclaimer'),
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        if (_tileFailed) ...[
          SizedBox(height: SimSpace.sm),
          SimNotice(text: tr('sim.map_failed'), error: true),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              key: const ValueKey('retry-basemap'),
              size: ShadButtonSize.sm,
              onPressed: () => setState(() {
                _tileFailed = false;
                _attempt++;
              }),
              child: Text(tr('sim.retry_basemap')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _plot(BuildContext context, List<LocationFix> points) => ColoredBox(
    color: context.colors.surfaceContainerLow,
    child: Semantics(
      label: tr('sim.coordinate_plot'),
      child: CustomPaint(
        painter: _CoordinatePainter(
          route: widget.route?.points ?? const [],
          location: widget.location,
          line: context.colors.primary,
          grid: context.colors.outlineVariant.withValues(alpha: .6),
          markerBorder: context.colors.surface,
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(SimSpace.ms),
            child: Text(
              tr(
                'sim.plot_bounds',
                namedArgs: {
                  'lat':
                      '${points.map((p) => p.latitude).reduce(math.min).toStringAsFixed(5)} … ${points.map((p) => p.latitude).reduce(math.max).toStringAsFixed(5)}',
                  'lon':
                      '${points.map((p) => p.longitude).reduce(math.min).toStringAsFixed(5)} … ${points.map((p) => p.longitude).reduce(math.max).toStringAsFixed(5)}',
                },
              ),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tiles(
    BuildContext context,
    List<LocationFix> points,
    BasemapSource source,
  ) {
    LatLng project(LocationFix point) => basemapCoordinates(
      LatLng(point.latitude, point.longitude),
      source.settings,
    );
    final coordinates = points.map(project).toList();
    final unique = coordinates.map((p) => (p.latitude, p.longitude)).toSet();
    final attempt = _attempt;
    return FlutterMap(
      key: ValueKey((widget.route?.id ?? 'position', source.settings, attempt)),
      options: MapOptions(
        crs: source.crs,
        minZoom: 3,
        maxZoom: source.maxZoom,
        initialCenter: coordinates.first,
        initialZoom: 14,
        initialCameraFit: unique.length < 2
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(coordinates),
                padding: EdgeInsets.all(SimSpace.xl),
                maxZoom: 16,
              ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        BasemapTileLayer(source: source, onError: () => _fallback(attempt)),
        if (widget.route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.route!.points.map(project).toList(),
                color: context.colors.primary,
                strokeWidth: 3,
              ),
            ],
          ),
        if (widget.location case final point?)
          MarkerLayer(
            markers: [
              Marker(
                point: project(point),
                width: 24,
                height: 24,
                child: Icon(
                  Icons.location_on,
                  color: context.colors.primary,
                  size: 24,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CoordinatePainter extends CustomPainter {
  _CoordinatePainter({
    required this.route,
    required this.location,
    required this.line,
    required this.grid,
    required this.markerBorder,
  });
  final List<LocationFix> route;
  final LocationFix? location;
  final Color line, grid, markerBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [...route, ?location];
    if (points.isEmpty) return;
    final area = Rect.fromLTWH(
      28,
      24,
      math.max(1, size.width - 56),
      math.max(1, size.height - 92),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final fraction = i / 4;
      canvas.drawLine(
        Offset(area.left + area.width * fraction, area.top),
        Offset(area.left + area.width * fraction, area.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(area.left, area.top + area.height * fraction),
        Offset(area.right, area.top + area.height * fraction),
        gridPaint,
      );
    }
    final midLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final cosLat = math.cos(midLat * math.pi / 180).abs().clamp(.01, 1.0);
    final xs = points.map((p) => p.longitude * cosLat).toList();
    final ys = points.map((p) => p.latitude).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final xRange = math.max(maxX - minX, .0001),
        yRange = math.max(maxY - minY, .0001);
    final scale = math.min(area.width / xRange, area.height / yRange) * .85;
    Offset project(LocationFix point) => Offset(
      area.center.dx + (point.longitude * cosLat - (minX + maxX) / 2) * scale,
      area.center.dy - (point.latitude - (minY + maxY) / 2) * scale,
    );
    if (route.isNotEmpty) {
      final path = Path()
        ..moveTo(project(route.first).dx, project(route.first).dy);
      for (final point in route.skip(1)) {
        final position = project(point);
        path.lineTo(position.dx, position.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(project(route.first), 4, Paint()..color = line);
      canvas.drawCircle(project(route.last), 4, Paint()..color = line);
    }
    if (location != null) {
      canvas.drawCircle(project(location!), 7, Paint()..color = markerBorder);
      canvas.drawCircle(project(location!), 5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_CoordinatePainter oldDelegate) =>
      oldDelegate.route != route ||
      oldDelegate.location != location ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}
