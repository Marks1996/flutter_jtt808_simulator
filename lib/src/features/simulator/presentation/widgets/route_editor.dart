import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/route_planning_provider.dart';
import '../providers/simulator_provider.dart';
import 'route_planning_panel.dart';
import 'route_preview.dart';
import 'sim_ui.dart';

Future<void> showRouteEditor(
  BuildContext context,
  SimulatorController controller, [
  DriveRoute? route,
]) => showShadDialog<void>(
  context: context,
  builder: (_) => RouteEditor(controller: controller, route: route),
);

class RouteEditor extends ConsumerStatefulWidget {
  const RouteEditor({super.key, required this.controller, this.route});
  final SimulatorController controller;
  final DriveRoute? route;
  @override
  ConsumerState<RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends ConsumerState<RouteEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.route?.name ?? '');
  late final _csv = TextEditingController(
    text: widget.route == null
        ? '# WGS84\nlatitude,longitude,speed\n'
        : RouteCsv.encode(widget.route!),
  );
  late final _speed = TextEditingController(
    text: '${widget.route?.points.first.speed ?? 40}',
  );
  late final _id = widget.route?.id ?? widget.controller.newId();
  late DriveRoute? _preview = widget.route;
  late RoutePlanMetadata? _planning = widget.route?.planning;
  late final RoutePlanningController _draft;
  late int _mode = widget.route == null || widget.route?.planning != null
      ? 0
      : 1;
  bool _stale = false;
  bool _visualPending = false;
  bool _changingCsv = false;
  RequestState<void> _save = const RequestInitial();
  late final String _initialName, _initialCsv, _initialSpeed;

  @override
  void initState() {
    super.initState();
    _initialName = _name.text;
    _initialCsv = _csv.text;
    _initialSpeed = _speed.text;
    final route = widget.route;
    _draft = RoutePlanningController(
      ref.read(routePlannerProvider),
      waypoints:
          route?.planning?.waypoints ??
          [
            if (route != null) ...[
              RouteWaypoint(
                route.points.first.latitude,
                route.points.first.longitude,
              ),
              RouteWaypoint(
                route.points.last.latitude,
                route.points.last.longitude,
              ),
            ],
          ],
    );
    if (route?.planning case final origin?) {
      _draft.state = RequestSuccess(
        PlannedRoute(
          origin: origin,
          points: [
            for (final point in route!.points)
              RouteWaypoint(point.latitude, point.longitude),
          ],
        ),
      );
    }
    _draft.addListener(_draftChanged);
    ref.listenManual(simulatorProvider.select((c) => c.workspace.routing), (
      _,
      _,
    ) {
      _draft.invalidate();
      setState(() => _visualPending = true);
    });
  }

  bool get _hasChanges =>
      _name.text != _initialName ||
      _csv.text != _initialCsv ||
      _speed.text != _initialSpeed ||
      _draft.hasChanges;

  @override
  void dispose() {
    _draft.removeListener(_draftChanged);
    _draft.dispose();
    _name.dispose();
    _csv.dispose();
    _speed.dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (_changingCsv || !mounted) return;
    setState(() {
      if (_draft.state case RequestSuccess(:final data)) {
        _applyPlan(data);
      } else {
        _visualPending = true;
        _preview = null;
      }
      _save = const RequestInitial();
    });
  }

  void _applyPlan(PlannedRoute data) {
    final speed = double.tryParse(_speed.text);
    if (speed == null || !speed.isFinite || speed < 1 || speed > 200) {
      _visualPending = true;
      _preview = null;
      return;
    }
    final route = DriveRoute(
      id: _id,
      name: _name.text.trim(),
      planning: data.origin,
      points: [
        for (final p in data.points)
          LocationFix(
            latitude: p.latitude,
            longitude: p.longitude,
            speed: speed,
          ),
      ],
    );
    // ShadInputFormField also calls onChanged for controller writes. Keep
    // generated CSV synchronization from invalidating its own planned result.
    _changingCsv = true;
    _csv.text = RouteCsv.encode(route);
    _changingCsv = false;
    _planning = data.origin;
    _preview = route;
    _stale = false;
    _visualPending = false;
  }

  DriveRoute _parse() {
    if (_visualPending || (_mode == 0 && !_draft.state.isSuccess)) {
      throw const FormatException('routing_stale');
    }
    final route = RouteCsv.parse(_csv.text, id: _id, name: _name.text.trim());
    return DriveRoute(
      id: route.id,
      name: route.name,
      points: route.points,
      planning: _planning,
    );
  }

  void _refresh() {
    if (!_form.currentState!.validate()) return;
    try {
      final value = _parse();
      setState(() {
        _preview = value;
        _stale = false;
        _save = const RequestInitial();
      });
    } catch (error) {
      setState(
        () => _save = RequestFailure(
          UnknownFailure(simError(error), error: error),
        ),
      );
    }
  }

  void _csvChanged() {
    if (_changingCsv) return;
    _changingCsv = true;
    _draft.invalidate();
    _changingCsv = false;
    setState(() {
      _stale = true;
      _visualPending = false;
      _preview = null;
      _planning = null;
    });
  }

  void _setCsv(String text) {
    _changingCsv = true;
    _csv.text = text;
    _changingCsv = false;
    _csvChanged();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _save = const RequestLoading());
    try {
      await widget.controller.saveRoute(_parse());
      if (!mounted) return;
      if (widget.controller.saveState.isFailure) {
        setState(
          () => _save = RequestFailure(CacheFailure(tr('sim.save_failure'))),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _save = RequestFailure(
            UnknownFailure(simError(error), error: error),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final blocked = widget.controller.tasks.any(
        (task) =>
            task.routeId == _id &&
            [
              TaskPhase.running,
              TaskPhase.paused,
            ].contains(widget.controller.taskRuntimes[task.id]?.phase),
      );
      final canSave =
          !_save.isLoading &&
          !blocked &&
          !_draft.state.isLoading &&
          (_mode == 1 || (_draft.state.isSuccess && !_visualPending));
      return SimEditGuard(
        hasChanges: () => _hasChanges,
        isSaving: () => _save.isLoading,
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 1040,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          titlePinned: true,
          descriptionPinned: true,
          // Keep map gestures and form controls clear of the dialog scrollbar.
          scrollPadding: EdgeInsetsDirectional.only(end: SimSpace.lg),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          closeIcon: ShadIconButton.ghost(
            key: const ValueKey('dialog-close'),
            icon: Icon(LucideIcons.x, size: 16, semanticLabel: tr('sim.close')),
            width: 20,
            height: 20,
            padding: EdgeInsets.zero,
            foregroundColor: ShadTheme.of(
              context,
            ).colorScheme.foreground.withValues(alpha: .5),
            hoverBackgroundColor: Colors.transparent,
            hoverForegroundColor: ShadTheme.of(context).colorScheme.foreground,
            pressedForegroundColor: ShadTheme.of(
              context,
            ).colorScheme.foreground,
            enabled: !_save.isLoading,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            tr(widget.route == null ? 'sim.create_route' : 'sim.edit_route'),
          ),
          description: Text(tr('sim.dialog.route_description')),
          actions: [
            ShadButton.outline(
              enabled: !_save.isLoading,
              onPressed: _save.isLoading
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: Text(tr('sim.cancel')),
            ),
            ShadButton(
              key: const ValueKey('save-route'),
              enabled: canSave,
              onPressed: canSave ? _submit : null,
              child: Text(
                tr(_save.isLoading ? 'sim.saving' : 'sim.save_route'),
              ),
            ),
          ],
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (blocked) ...[
                  SimNotice(
                    text: tr('sim.errors.stop_before_edit'),
                    error: true,
                  ),
                  SizedBox(height: SimSpace.md),
                ],
                if (_save case RequestFailure(:final failure)) ...[
                  SimNotice(text: failure.message, error: true),
                  SizedBox(height: SimSpace.md),
                ],
                SimField(
                  key: const ValueKey('route-name'),
                  label: tr('sim.route_name'),
                  controller: _name,
                  enabled: !_save.isLoading,
                  validator: simRequired,
                ),
                SizedBox(height: SimSpace.md),
                ShadTabs<int>(
                  value: _mode,
                  onChanged: (value) => setState(() => _mode = value),
                  tabs: [
                    ShadTab(
                      value: 0,
                      content: RoutePlanningPanel(
                        draft: _draft,
                        speed: _speed,
                        enabled: !_save.isLoading && !blocked,
                        onSpeedChanged: () {
                          if (_draft.state case RequestSuccess(:final data)) {
                            setState(() => _applyPlan(data));
                          }
                        },
                      ),
                      child: Expanded(
                        child: Text(
                          tr('sim.routing.visual_tab'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ShadTab(
                      value: 1,
                      content: _csvLayout(context),
                      child: Expanded(
                        child: Text(
                          tr('sim.routing.csv_tab'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_preview case final route?) ...[
                  SizedBox(height: SimSpace.md),
                  Text(
                    tr(
                      'sim.route_summary',
                      namedArgs: {
                        'points': '${route.points.length}',
                        'distance': route.distanceKm.toStringAsFixed(2),
                      },
                    ),
                    style: simNumberStyle(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _csvLayout(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final editor = _csvEditor(context);
      final route = _preview;
      if (route == null) return editor;
      final preview = RoutePreview(
        route: route,
        height: constraints.maxWidth >= 800 ? 340 : 160,
      );
      if (constraints.maxWidth >= 800) {
        return Row(
          key: const ValueKey('route-csv-split'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: editor),
            SizedBox(width: SimSpace.xl),
            Expanded(flex: 7, child: preview),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editor,
          SizedBox(height: SimSpace.md),
          preview,
        ],
      );
    },
  );

  Widget _csvEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SimNotice(text: tr('sim.route_format_help')),
      SizedBox(height: SimSpace.md),
      Wrap(
        spacing: SimSpace.sm,
        runSpacing: SimSpace.sm,
        children: [
          SimButton(
            label: tr('sim.paste_csv'),
            icon: Icons.content_paste_outlined,
            onPressed: _save.isLoading
                ? null
                : () => simRun(context, () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (mounted && data?.text != null) _setCsv(data!.text!);
                  }),
          ),
          SimButton(
            label: tr('sim.import_file'),
            icon: Icons.upload_file_outlined,
            onPressed: _save.isLoading
                ? null
                : () => simRun(context, () async {
                    final text = await simPickText(extensions: ['csv', 'txt']);
                    if (mounted && text != null) _setCsv(text);
                  }),
          ),
          SimButton(
            label: tr('sim.copy_csv'),
            icon: Icons.copy_outlined,
            onPressed: () => simCopy(context, _csv.text),
          ),
          SimButton(
            label: tr('sim.example_polyline'),
            onPressed: _save.isLoading ? null : () => _setCsv(RouteCsv.example),
          ),
        ],
      ),
      SizedBox(height: SimSpace.md),
      SimField(
        key: const ValueKey('route-csv'),
        label: tr('sim.route_csv'),
        controller: _csv,
        enabled: !_save.isLoading,
        maxLines: 10,
        minLines: 5,
        validator: simRequired,
        onChanged: (_) => _csvChanged(),
      ),
      SizedBox(height: SimSpace.md),
      Wrap(
        spacing: SimSpace.md,
        runSpacing: SimSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SimButton(
            label: tr('sim.preview_route'),
            icon: Icons.polyline_outlined,
            onPressed: _save.isLoading ? null : _refresh,
          ),
          if (_stale)
            Text(tr('sim.preview_stale'), style: context.textTheme.bodySmall),
        ],
      ),
    ],
  );
}
