import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/simulator_provider.dart';
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

class RouteEditor extends StatefulWidget {
  const RouteEditor({super.key, required this.controller, this.route});
  final SimulatorController controller;
  final DriveRoute? route;

  @override
  State<RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends State<RouteEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.route?.name ?? '');
  late final _csv = TextEditingController(
    text: widget.route == null
        ? '# WGS84\nlatitude,longitude,speed\n'
        : RouteCsv.encode(widget.route!),
  );
  late final _id = widget.route?.id ?? widget.controller.newId();
  late DriveRoute? _preview = widget.route;
  bool _stale = false;
  RequestState<void> _save = const RequestInitial();
  late final String _initialName;
  late final String _initialCsv;

  @override
  void initState() {
    super.initState();
    _initialName = _name.text;
    _initialCsv = _csv.text;
  }

  bool get _hasChanges =>
      _name.text != _initialName || _csv.text != _initialCsv;

  @override
  void dispose() {
    _name.dispose();
    _csv.dispose();
    super.dispose();
  }

  DriveRoute _parse() {
    final route = RouteCsv.parse(_csv.text, id: _id, name: _name.text.trim());
    if (route.points.any((point) => point.speed < 1 || point.speed > 200)) {
      throw const FormatException('route_csv_invalid');
    }
    return route;
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

  void _setCsv(String text) => setState(() {
    _csv.text = text;
    _stale = true;
    _preview = null;
  });

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _save = const RequestLoading());
    try {
      await widget.controller.saveRoute(_parse());
      if (mounted) Navigator.pop(context);
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
      return SimEditGuard(
        hasChanges: () => _hasChanges,
        isSaving: () => _save.isLoading,
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          titlePinned: true,
          descriptionPinned: true,
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
              enabled: !_save.isLoading && !blocked,
              onPressed: _save.isLoading || blocked ? null : _submit,
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
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (mounted && data?.text != null) {
                                _setCsv(data!.text!);
                              }
                            }),
                    ),
                    SimButton(
                      label: tr('sim.import_file'),
                      icon: Icons.upload_file_outlined,
                      onPressed: _save.isLoading
                          ? null
                          : () => simRun(context, () async {
                              final text = await simPickText(
                                extensions: ['csv', 'txt'],
                              );
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
                      onPressed: _save.isLoading
                          ? null
                          : () => _setCsv(RouteCsv.example),
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
                  onChanged: (_) => setState(() => _stale = true),
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
                      Text(
                        tr('sim.preview_stale'),
                        style: context.textTheme.bodySmall,
                      ),
                    if (_preview case final route?)
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
                ),
                if (_preview case final route?) ...[
                  SizedBox(height: SimSpace.md),
                  RoutePreview(route: route, height: 160),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
