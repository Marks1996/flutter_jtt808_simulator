import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

Future<void> showWorkspaceTransfer(
  BuildContext context,
  SimulatorController controller, {
  required bool importing,
}) => showShadDialog<void>(
  context: context,
  builder: (_) =>
      _WorkspaceTransfer(controller: controller, importing: importing),
);

class _WorkspaceTransfer extends StatefulWidget {
  const _WorkspaceTransfer({required this.controller, required this.importing});
  final SimulatorController controller;
  final bool importing;

  @override
  State<_WorkspaceTransfer> createState() => _WorkspaceTransferState();
}

class _WorkspaceTransferState extends State<_WorkspaceTransfer> {
  late final _text = TextEditingController(
    text: widget.importing ? '' : widget.controller.exportWorkspace(),
  );
  RequestState<void> _operation = const RequestInitial();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    SimulatorWorkspace workspace;
    try {
      workspace = SimulatorWorkspace.fromJson(
        Map<String, Object?>.from(jsonDecode(_text.text) as Map),
      );
      for (final route in workspace.routes) {
        RouteCsv.parse(RouteCsv.encode(route), id: route.id, name: route.name);
        if (route.points.any((point) => point.speed < 1 || point.speed > 200)) {
          throw const FormatException('invalid_workspace');
        }
      }
    } catch (error) {
      setState(
        () => _operation = RequestFailure(
          UnknownFailure(tr('sim.errors.invalid_workspace'), error: error),
        ),
      );
      return;
    }
    final confirmed = await simConfirm(
      context,
      title: tr('sim.replace_workspace'),
      body: tr(
        'sim.replace_workspace_confirm',
        namedArgs: {
          'terminals': '${workspace.terminals.length}',
          'routes': '${workspace.routes.length}',
          'tasks': '${workspace.tasks.length}',
        },
      ),
      confirm: tr('sim.disconnect_and_import'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _operation = const RequestLoading());
    try {
      await widget.controller.disconnectAll();
      await widget.controller.importWorkspace(_text.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _operation = RequestFailure(
            UnknownFailure(simError(error), error: error),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SimEditGuard(
    hasChanges: () => widget.importing && _text.text.isNotEmpty,
    isSaving: () => _operation.isLoading,
    child: ShadDialog(
      constraints: BoxConstraints(
        maxWidth: 800,
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
        pressedForegroundColor: ShadTheme.of(context).colorScheme.foreground,
        enabled: !_operation.isLoading,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        tr(widget.importing ? 'sim.import_workspace' : 'sim.export_workspace'),
      ),
      description: Text(
        tr(
          widget.importing
              ? 'sim.dialog.import_description'
              : 'sim.dialog.export_description',
        ),
      ),
      actions: [
        ShadButton.outline(
          enabled: !_operation.isLoading,
          onPressed: _operation.isLoading
              ? null
              : () => Navigator.of(context).maybePop(),
          child: Text(tr('sim.close')),
        ),
        if (widget.importing)
          ShadButton(
            enabled: !_operation.isLoading,
            onPressed: _operation.isLoading ? null : _import,
            child: Text(
              tr(_operation.isLoading ? 'sim.saving' : 'sim.review_import'),
            ),
          )
        else
          ShadButton(
            leading: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () => simCopy(context, _text.text),
            child: Text(tr('sim.copy_json')),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SimNotice(text: tr('sim.workspace_secret_warning')),
          SizedBox(height: SimSpace.md),
          if (_operation case RequestFailure(:final failure)) ...[
            SimNotice(text: failure.message, error: true),
            SizedBox(height: SimSpace.md),
          ],
          if (widget.importing) ...[
            Wrap(
              spacing: SimSpace.sm,
              runSpacing: SimSpace.sm,
              children: [
                SimButton(
                  label: tr('sim.paste_json'),
                  icon: Icons.content_paste_outlined,
                  onPressed: _operation.isLoading
                      ? null
                      : () => simRun(context, () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (mounted && data?.text != null) {
                            setState(() => _text.text = data!.text!);
                          }
                        }),
                ),
                SimButton(
                  label: tr('sim.import_file'),
                  icon: Icons.upload_file_outlined,
                  onPressed: _operation.isLoading
                      ? null
                      : () => simRun(context, () async {
                          final value = await simPickText(extensions: ['json']);
                          if (mounted && value != null) {
                            setState(() => _text.text = value);
                          }
                        }),
                ),
              ],
            ),
            SizedBox(height: SimSpace.md),
            SimField(
              key: const ValueKey('workspace-json'),
              label: tr('sim.workspace_json'),
              controller: _text,
              maxLines: 18,
              minLines: 10,
              enabled: !_operation.isLoading,
            ),
          ] else
            Container(
              padding: EdgeInsets.all(SimSpace.ms),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: AppBorders.input,
              ),
              child: SelectableText(_text.text, style: simNumberStyle(context)),
            ),
        ],
      ),
    ),
  );
}
