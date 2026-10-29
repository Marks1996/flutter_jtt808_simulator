import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

Future<void> showTaskEditor(
  BuildContext context,
  SimulatorController controller, [
  DriveTask? task,
]) => showShadDialog<void>(
  context: context,
  builder: (_) => TaskEditor(controller: controller, task: task),
);

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.controller, this.task});
  final SimulatorController controller;
  final DriveTask? task;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.task?.name ?? '');
  late String? _terminalId = widget.task?.terminalId;
  late String? _routeId = widget.task?.routeId;
  late bool _loop = widget.task?.loop ?? false;
  RequestState<void> _save = const RequestInitial();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _name.text != (widget.task?.name ?? '') ||
      _terminalId != widget.task?.terminalId ||
      _routeId != widget.task?.routeId ||
      _loop != (widget.task?.loop ?? false);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _save = const RequestLoading());
    try {
      await widget.controller.saveTask(
        DriveTask(
          id: widget.task?.id ?? widget.controller.newId(),
          name: _name.text.trim(),
          terminalId: _terminalId!,
          routeId: _routeId!,
          loop: _loop,
        ),
      );
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
      final c = widget.controller;
      final blocked = [
        TaskPhase.running,
        TaskPhase.paused,
      ].contains(c.taskRuntimes[widget.task?.id]?.phase);
      return SimEditGuard(
        hasChanges: () => _hasChanges,
        isSaving: () => _save.isLoading,
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 560,
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
            tr(widget.task == null ? 'sim.create_task' : 'sim.edit_task'),
          ),
          description: Text(tr('sim.dialog.task_description')),
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
              child: Text(tr(_save.isLoading ? 'sim.saving' : 'sim.save_task')),
            ),
          ],
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_save case RequestFailure(:final failure)) ...[
                  SimNotice(text: failure.message, error: true),
                  SizedBox(height: SimSpace.md),
                ],
                if (blocked) ...[
                  SimNotice(
                    text: tr('sim.errors.stop_before_edit'),
                    error: true,
                  ),
                  SizedBox(height: SimSpace.md),
                ],
                SimField(
                  key: const ValueKey('task-name'),
                  label: tr('sim.task_name'),
                  controller: _name,
                  enabled: !_save.isLoading,
                  validator: simRequired,
                ),
                SizedBox(height: SimSpace.md),
                SimSelect<String>(
                  label: tr('sim.terminal'),
                  value: c.terminals.any((t) => t.id == _terminalId)
                      ? _terminalId
                      : null,
                  items: c.terminals
                      .map(
                        (t) => SimOption(
                          value: t.id,
                          child: Text(
                            '${t.name} · ${t.phone}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? tr('sim.errors.task_dependencies') : null,
                  onChanged: _save.isLoading
                      ? null
                      : (value) => setState(() => _terminalId = value),
                ),
                SizedBox(height: SimSpace.md),
                SimSelect<String>(
                  label: tr('sim.route'),
                  value: c.routes.any((r) => r.id == _routeId)
                      ? _routeId
                      : null,
                  items: c.routes
                      .map(
                        (r) => SimOption(
                          value: r.id,
                          child: Text(r.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? tr('sim.errors.task_dependencies') : null,
                  onChanged: _save.isLoading
                      ? null
                      : (value) => setState(() => _routeId = value),
                ),
                SizedBox(height: SimSpace.md),
                ShadSwitch(
                  value: _loop,
                  enabled: !_save.isLoading,
                  label: Text(
                    tr('sim.loop'),
                    style: context.textTheme.bodyMedium,
                  ),
                  sublabel: Text(
                    tr('sim.loop_hint'),
                    style: context.textTheme.bodySmall,
                  ),
                  onChanged: (value) => setState(() => _loop = value),
                ),
                SizedBox(height: SimSpace.md),
                SimNotice(text: tr('sim.task_start_hint')),
              ],
            ),
          ),
        ),
      );
    },
  );
}
