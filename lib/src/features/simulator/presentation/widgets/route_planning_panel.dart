import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/route_planning_provider.dart';
import '../providers/simulator_provider.dart';
import 'route_planning_map.dart';
import 'route_data_links.dart';
import 'sim_ui.dart';

class RoutePlanningPanel extends ConsumerStatefulWidget {
  const RoutePlanningPanel({
    super.key,
    required this.draft,
    required this.speed,
    required this.onSpeedChanged,
    this.enabled = true,
  });
  final RoutePlanningController draft;
  final TextEditingController speed;
  final VoidCallback onSpeedChanged;
  final bool enabled;

  @override
  ConsumerState<RoutePlanningPanel> createState() => _RoutePlanningPanelState();
}

class _RoutePlanningPanelState extends ConsumerState<RoutePlanningPanel> {
  final _coordinate = TextEditingController();
  int? _selected;
  String? _coordinateError;

  @override
  void dispose() {
    _coordinate.dispose();
    super.dispose();
  }

  void _select(int index) => setState(() {
    _selected = index;
    final point = widget.draft.waypoints[index];
    _coordinate.text =
        '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
    _coordinateError = null;
  });

  void _pick(RouteWaypoint point) {
    final index = _selected;
    if (index != null && index < widget.draft.waypoints.length) {
      widget.draft.update(index, point);
    } else {
      widget.draft.add(point);
    }
    setState(() {
      _selected = null;
      _coordinate.clear();
      _coordinateError = null;
    });
  }

  void _enter() {
    final values = _coordinate.text
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .toList();
    if (values.length != 2 ||
        values.any((v) => v == null) ||
        !RouteWaypoint(values[0]!, values[1]!).isValid) {
      setState(() => _coordinateError = 'invalid_coordinates');
      return;
    }
    _pick(RouteWaypoint(values[0]!, values[1]!));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(
      simulatorProvider.select((c) => c.workspace.routing),
    );
    final draft = widget.draft;
    final points = draft.waypoints;
    final result = switch (draft.state) {
      RequestSuccess(:final data) => data,
      _ => null,
    };
    final controls = Column(
      key: const ValueKey('route-planning-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            _selected == null
                ? 'sim.routing.add_hint'
                : 'sim.routing.replace_hint',
            namedArgs: {'number': '${(_selected ?? 0) + 1}'},
          ),
          style: context.textTheme.bodySmall,
        ),
        SizedBox(height: SimSpace.ms),
        SimField(
          key: const ValueKey('route-waypoint-coordinate'),
          label: tr('sim.routing.coordinate'),
          controller: _coordinate,
          enabled: widget.enabled,
          onChanged: (_) => setState(() => _coordinateError = null),
        ),
        if (_coordinateError != null)
          Text(
            tr('sim.errors.$_coordinateError'),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.error,
            ),
          ),
        SizedBox(height: SimSpace.ms),
        Wrap(
          spacing: SimSpace.ms,
          runSpacing: SimSpace.ms,
          children: [
            ShadButton.outline(
              key: const ValueKey('route-add-waypoint'),
              size: ShadButtonSize.sm,
              enabled:
                  widget.enabled &&
                  (_selected != null ||
                      points.length < RoutePlanMetadata.maxWaypoints),
              onPressed: _enter,
              child: Text(
                tr(
                  _selected == null
                      ? 'sim.routing.add_coordinate'
                      : 'sim.routing.replace_coordinate',
                ),
              ),
            ),
            if (_selected != null)
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: () => setState(() {
                  _selected = null;
                  _coordinate.clear();
                }),
                child: Text(tr('sim.routing.continue_adding')),
              ),
            if (points.isNotEmpty)
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                enabled: widget.enabled,
                onPressed: () {
                  draft.replace([]);
                  setState(() {
                    _selected = null;
                    _coordinate.clear();
                  });
                },
                child: Text(tr('sim.routing.clear_points')),
              ),
          ],
        ),
        if (points.isNotEmpty) ...[
          SizedBox(height: SimSpace.md),
          for (var i = 0; i < points.length; i++)
            Row(
              children: [
                Expanded(
                  child: ShadButton.ghost(
                    key: ValueKey('route-waypoint-$i'),
                    height: 0,
                    expands: true,
                    mainAxisAlignment: MainAxisAlignment.start,
                    backgroundColor: _selected == i
                        ? context.colors.surfaceContainerHigh
                        : null,
                    enabled: widget.enabled,
                    onPressed: () => _select(i),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(
                            i == 0
                                ? 'sim.routing.origin'
                                : i == points.length - 1
                                ? 'sim.routing.destination'
                                : 'sim.routing.stop',
                            namedArgs: {'number': '${i + 1}'},
                          ),
                        ),
                        Text(
                          '${points[i].latitude.toStringAsFixed(6)}, ${points[i].longitude.toStringAsFixed(6)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                SimIconButton(
                  tooltip: tr('sim.routing.move_up'),
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  onPressed: !widget.enabled || i == 0
                      ? null
                      : () {
                          draft.move(i, -1);
                          setState(() => _selected = null);
                        },
                ),
                SimIconButton(
                  tooltip: tr('sim.routing.move_down'),
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  onPressed: !widget.enabled || i == points.length - 1
                      ? null
                      : () {
                          draft.move(i, 1);
                          setState(() => _selected = null);
                        },
                ),
                SimIconButton(
                  tooltip: tr('sim.routing.remove_point'),
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: !widget.enabled
                      ? null
                      : () {
                          draft.remove(i);
                          setState(() => _selected = null);
                        },
                ),
              ],
            ),
        ],
        SizedBox(height: SimSpace.md),
        SimField(
          key: const ValueKey('route-planned-speed'),
          label: tr('sim.routing.speed'),
          controller: widget.speed,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          validator: (text) {
            final value = double.tryParse(text ?? '');
            return value == null || !value.isFinite || value < 1 || value > 200
                ? tr('sim.errors.route_csv_invalid')
                : null;
          },
          onChanged: (_) => widget.onSpeedChanged(),
        ),
        SizedBox(height: SimSpace.md),
        Text(
          tr(
            'sim.routing.selected_provider',
            namedArgs: {
              'provider': tr('sim.routing.provider.${settings.provider.name}'),
            },
          ),
          style: context.textTheme.labelMedium,
        ),
        SizedBox(height: SimSpace.sm),
        Text(
          tr('sim.routing.request_hint'),
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        if (settings.usesPublicOsrm) ...[
          SizedBox(height: SimSpace.ms),
          Text(
            tr('sim.routing.demo_warning'),
            style: context.textTheme.bodySmall,
          ),
        ],
        if (settings.planningValidationKey case final key?) ...[
          SizedBox(height: SimSpace.ms),
          SimNotice(text: tr('sim.errors.$key'), error: true),
        ],
        if (draft.state case RequestFailure(:final failure)) ...[
          SizedBox(height: SimSpace.md),
          SimNotice(text: tr('sim.errors.${failure.message}'), error: true),
        ],
        SizedBox(height: SimSpace.md),
        Wrap(
          spacing: SimSpace.ms,
          runSpacing: SimSpace.ms,
          children: [
            ShadButton(
              key: const ValueKey('plan-route'),
              enabled:
                  widget.enabled &&
                  !draft.state.isLoading &&
                  points.length >= 2 &&
                  settings.planningValidationKey == null,
              onPressed: () => draft.plan(settings),
              child: Text(
                tr(
                  draft.state.isLoading
                      ? 'sim.routing.loading'
                      : 'sim.routing.plan',
                ),
              ),
            ),
            if (draft.state.isLoading)
              ShadButton.outline(
                onPressed: draft.invalidate,
                child: Text(tr('sim.routing.cancel')),
              ),
          ],
        ),
        if (result != null) ...[
          SizedBox(height: SimSpace.md),
          Text(
            tr(
              'sim.routing.ready',
              namedArgs: {'points': '${result.points.length}'},
            ),
            style: context.textTheme.bodySmall,
          ),
          Text(
            tr('sim.routing.attribution.${result.origin.provider.name}'),
            style: context.textTheme.bodySmall,
          ),
          if (result.origin.provider == RoutingProvider.osrm)
            const RouteDataLinks(),
        ],
      ],
    );
    final map = Column(
      key: const ValueKey('route-planning-map-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('sim.routing.pick_help'), style: context.textTheme.bodySmall),
        SizedBox(height: SimSpace.md),
        RoutePlanningMap(
          waypoints: points,
          selected: _selected,
          geometry: result?.points ?? const [],
          enabled: widget.enabled,
          // At capacity, block adding a point, not selecting existing markers.
          canPick:
              _selected != null ||
              points.length < RoutePlanMetadata.maxWaypoints,
          onSelected: _select,
          onPicked: _pick,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Row(
            key: const ValueKey('route-planning-split'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: controls),
              SizedBox(width: SimSpace.xl),
              Expanded(flex: 7, child: map),
            ],
          );
        }
        return Column(
          key: const ValueKey('route-planning-stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            map,
            SizedBox(height: SimSpace.md),
            controls,
          ],
        );
      },
    );
  }
}
