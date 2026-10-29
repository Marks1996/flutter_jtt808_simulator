import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../services/desktop_window_service.dart';
import '../providers/simulator_provider.dart';
import '../widgets/sim_ui.dart';
import '../widgets/terminal_editor.dart';

class TerminalsPage extends StatelessWidget {
  const TerminalsPage({
    super.key,
    required this.controller,
    required this.onOpenTerminal,
  });
  final SimulatorController controller;
  final ValueChanged<String> onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SimPage(
      title: tr('sim.terminals'),
      subtitle: tr('sim.terminals_subtitle'),
      actions: [
        if (c.terminals.isNotEmpty) ...[
          SimButton(
            label: tr('sim.connect_all'),
            onPressed: () => simRun(context, c.connectAll),
          ),
          SimButton(
            label: tr('sim.disconnect_all'),
            onPressed: c.terminals.any((t) => c.runtime(t.id).busy)
                ? () => simRun(context, c.disconnectAll)
                : null,
          ),
        ],
        if (c.terminals.isNotEmpty)
          SimButton(
            key: const ValueKey('create-terminal'),
            label: tr('sim.create_terminal'),
            primary: true,
            icon: Icons.add,
            onPressed: () => showTerminalEditor(context, c),
          ),
      ],
      children: [
        if (c.terminals.isEmpty)
          SimPanel(
            child: SimEmpty(
              title: tr('sim.no_terminals'),
              message: tr('sim.no_terminals_management'),
              action: SimButton(
                key: const ValueKey('create-terminal'),
                label: tr('sim.create_terminal'),
                primary: true,
                icon: Icons.add,
                onPressed: () => showTerminalEditor(context, c),
              ),
            ),
          )
        else
          SimPanel(
            padding: false,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  DesktopWindowService.isSupported ||
                      constraints.maxWidth >= 960
                  ? _table(context)
                  : Column(
                      children: [
                        for (final terminal in c.terminals)
                          _compactRow(context, terminal),
                      ],
                    ),
            ),
          ),
        if (c.terminals.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              tr('sim.terminals_help'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _table(BuildContext context) {
    final labelStyle = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 36,
            child: _columns(
              identity: Text(tr('sim.terminal'), style: labelStyle),
              host: Text(tr('sim.server'), style: labelStyle),
              status: Text(tr('sim.connection'), style: labelStyle),
              traffic: Text(
                tr('sim.messages_sent_received'),
                textAlign: TextAlign.end,
                style: labelStyle,
              ),
              actions: Text(
                tr('sim.actions'),
                textAlign: TextAlign.end,
                style: labelStyle,
              ),
            ),
          ),
        ),
        for (final terminal in controller.terminals)
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: _columns(
              identity: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    terminal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    terminal.phone,
                    maxLines: 1,
                    style: simNumberStyle(context)?.copyWith(
                      fontSize: 12,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              host: Text(
                '${terminal.host}:${terminal.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: simNumberStyle(
                  context,
                )?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              status: SimPhase(controller.runtime(terminal.id).phase),
              traffic: _traffic(context, terminal.id),
              actions: _actions(context, terminal),
            ),
          ),
      ],
    );
  }

  // The last three columns stay aligned; spare width belongs to identity/host.
  Widget _columns({
    required Widget identity,
    required Widget host,
    required Widget status,
    required Widget traffic,
    required Widget actions,
  }) => Row(
    children: [
      Expanded(flex: 5, child: identity),
      const SizedBox(width: 12),
      Expanded(flex: 4, child: host),
      const SizedBox(width: 12),
      SizedBox(width: 116, child: status),
      const SizedBox(width: 12),
      SizedBox(width: 104, child: traffic),
      const SizedBox(width: 16),
      SizedBox(
        width: DesktopWindowService.isSupported ? 216 : 248,
        child: actions,
      ),
    ],
  );

  Widget _compactRow(BuildContext context, TerminalConfig terminal) {
    final runtime = controller.runtime(terminal.id);
    final identity = '${terminal.phone} · ${terminal.host}:${terminal.port}';
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: terminal.id == controller.terminals.first.id
            ? null
            : Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        terminal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SimPhase(runtime.phase),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: ShadTooltip(
                        builder: (_) => Text(identity),
                        child: Text(
                          identity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _traffic(context, terminal.id),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SimIconButton(
            tooltip: tr(runtime.busy ? 'sim.disconnect' : 'sim.connect'),
            onPressed: () => _toggleConnection(context, terminal),
            icon: Icon(
              runtime.busy ? Icons.link_off_outlined : Icons.link_outlined,
              size: 18,
            ),
          ),
          _menu(context, terminal),
        ],
      ),
    );
  }

  Widget _traffic(BuildContext context, String id) {
    final runtime = controller.runtime(id);
    return ShadTooltip(
      builder: (_) => Text(
        tr(
          'sim.traffic_summary',
          namedArgs: {
            'sent': '${runtime.sent}',
            'received': '${runtime.received}',
          },
        ),
      ),
      child: Text(
        '${runtime.sent} / ${runtime.received}',
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: simNumberStyle(context),
      ),
    );
  }

  Widget _actions(BuildContext context, TerminalConfig terminal) {
    final runtime = controller.runtime(terminal.id);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: SimButton(
            label: tr(runtime.busy ? 'sim.disconnect' : 'sim.connect'),
            onPressed: () => _toggleConnection(context, terminal),
          ),
        ),
        const SizedBox(width: 4),
        SimIconButton(
          tooltip: tr('sim.open_console'),
          onPressed: () => onOpenTerminal(terminal.id),
          icon: const Icon(Icons.open_in_new, size: 18),
        ),
        SimIconButton(
          tooltip: tr(
            runtime.busy
                ? 'sim.errors.disconnect_before_edit'
                : 'sim.edit_terminal',
          ),
          onPressed: runtime.busy
              ? null
              : () => showTerminalEditor(context, controller, terminal),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
        SimIconButton(
          tooltip: tr(
            runtime.busy
                ? 'sim.errors.disconnect_before_edit'
                : 'sim.delete_terminal',
          ),
          onPressed: runtime.busy
              ? null
              : () => _deleteTerminal(context, terminal),
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context, TerminalConfig terminal) {
    final busy = controller.runtime(terminal.id).busy;
    return ShadMenubar(
      padding: EdgeInsets.zero,
      border: ShadBorder.none,
      items: [
        ShadMenubarItem(
          height: 44,
          width: 44,
          buttonPadding: EdgeInsets.zero,
          anchor: const ShadAnchorAuto(
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: Offset(0, 4),
          ),
          items: [
            ShadContextMenuItem(
              onPressed: () => onOpenTerminal(terminal.id),
              child: Text(tr('sim.open_console')),
            ),
            ShadContextMenuItem(
              enabled: !busy,
              onPressed: () =>
                  showTerminalEditor(context, controller, terminal),
              child: Text(
                tr(
                  busy
                      ? 'sim.errors.disconnect_before_edit'
                      : 'sim.edit_terminal',
                ),
              ),
            ),
            ShadContextMenuItem(
              enabled: !busy,
              onPressed: () => _deleteTerminal(context, terminal),
              child: Text(tr('sim.delete_terminal')),
            ),
          ],
          child: Semantics(
            label: tr('sim.actions'),
            child: const SizedBox(
              width: 24,
              height: 32,
              child: Icon(Icons.more_horiz, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleConnection(
    BuildContext context,
    TerminalConfig terminal,
  ) => simRun(
    context,
    () => controller.runtime(terminal.id).busy
        ? controller.disconnect(terminal.id)
        : controller.connect(terminal.id),
  );

  Future<void> _deleteTerminal(
    BuildContext context,
    TerminalConfig terminal,
  ) async {
    if (await simConfirm(
          context,
          title: tr('sim.delete_terminal'),
          body: tr('sim.delete_named', namedArgs: {'name': terminal.name}),
          destructive: true,
        ) &&
        context.mounted) {
      await simRun(context, () => controller.deleteTerminal(terminal.id));
    }
  }
}
