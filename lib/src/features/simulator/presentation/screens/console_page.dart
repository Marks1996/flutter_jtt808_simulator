import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import '../widgets/location_editor.dart';
import '../widgets/log_detail_dialog.dart';
import '../widgets/route_preview.dart';
import '../widgets/sim_ui.dart';
import '../widgets/task_controls.dart';
import '../widgets/terminal_editor.dart';

class ConsolePage extends StatelessWidget {
  const ConsolePage({
    super.key,
    required this.controller,
    required this.terminalId,
    required this.onTerminalChanged,
    required this.onNavigate,
  });
  final SimulatorController controller;
  final String? terminalId;
  final ValueChanged<String?> onTerminalChanged;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final terminal = terminalId == null ? null : c.terminal(terminalId!);
    final runtime = terminal == null ? null : c.runtime(terminal.id);
    final candidates = c.tasks.where((task) => task.terminalId == terminal?.id);
    final task =
        candidates
            .where(
              (task) => [
                TaskPhase.running,
                TaskPhase.paused,
              ].contains(c.taskRuntimes[task.id]?.phase),
            )
            .firstOrNull ??
        candidates.firstOrNull;
    final route = task == null ? null : c.route(task.routeId);
    final latest = c.logs
        .where((log) => log.terminalId == terminal?.id)
        .toList()
        .reversed
        .take(3)
        .toList();
    return SimPage(
      title: tr('sim.console'),
      subtitle: tr('sim.console_subtitle'),
      children: [
        _Statistics(controller: c),
        if (terminal == null)
          SimPanel(
            child: SimEmpty(
              title: tr('sim.no_terminals'),
              message: tr('sim.no_terminals_console'),
              icon: Icons.dns_outlined,
              action: SimButton(
                key: const ValueKey('console-create-terminal'),
                label: tr('sim.create_terminal'),
                primary: true,
                icon: Icons.add,
                onPressed: () => showTerminalEditor(context, c),
              ),
            ),
          )
        else ...[
          _connection(context, terminal, runtime!),
          LayoutBuilder(
            builder: (context, constraints) {
              final position = _position(context, runtime, route);
              final playback = _task(context, task);
              if (constraints.maxWidth < 740) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    position,
                    SizedBox(height: SimSpace.md),
                    playback,
                  ],
                );
              }
              // Content width = (5 + 4) flexible units + one 16px gutter.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: position),
                  SizedBox(width: SimSpace.lg),
                  Expanded(flex: 4, child: playback),
                ],
              );
            },
          ),
          _logs(context, latest),
          SimExpansion(
            key: PageStorageKey('manual-location-${terminal.id}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: SimSpace.md),
            title: Text(
              tr('sim.manual_location'),
              style: context.textTheme.titleSmall,
            ),
            subtitle: Text(
              tr('sim.manual_location_hint'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            children: [
              LocationEditor(
                key: ValueKey(terminal.id),
                controller: c,
                terminalId: terminal.id,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _connection(
    BuildContext context,
    TerminalConfig terminal,
    TerminalRuntime runtime,
  ) {
    final selector = SimSelect<String>(
      label: tr('sim.current_terminal'),
      compact: true,
      value: terminal.id,
      items: controller.terminals
          .map(
            (item) => SimOption(
              value: item.id,
              child: Text(
                '${item.name} · ${item.phone}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onTerminalChanged,
    );
    final identity = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: SimSpace.md,
      runSpacing: SimSpace.xs,
      children: [
        SimPhase(runtime.phase),
        Text('${terminal.host}:${terminal.port}', style: simCodeStyle(context)),
      ],
    );
    final actions = Wrap(
      spacing: SimSpace.sm,
      runSpacing: SimSpace.sm,
      children: [
        SimButton(
          label: tr(runtime.busy ? 'sim.disconnect' : 'sim.connect'),
          primary: !runtime.busy,
          icon: runtime.busy ? Icons.link_off : Icons.link,
          onPressed: () => simRun(
            context,
            () => runtime.busy
                ? controller.disconnect(terminal.id)
                : controller.connect(terminal.id),
          ),
        ),
        SimButton(
          label: tr('sim.heartbeat'),
          icon: Icons.favorite_border,
          onPressed: runtime.phase == ConnectionPhase.online
              ? () => simRun(context, () => controller.heartbeat(terminal.id))
              : null,
        ),
        SimButton(
          label: tr('sim.send_location'),
          icon: Icons.near_me_outlined,
          onPressed: runtime.phase == ConnectionPhase.online
              ? () =>
                    simRun(context, () => controller.sendLocation(terminal.id))
              : null,
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: SimSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 800) {
                  return Row(
                    children: [
                      SizedBox(width: 230, child: selector),
                      SizedBox(width: SimSpace.md),
                      Expanded(child: identity),
                      SizedBox(width: SimSpace.md),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .45,
                        ),
                        child: actions,
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth >= 500)
                      Row(
                        children: [
                          SizedBox(width: 250, child: selector),
                          SizedBox(width: SimSpace.md),
                          Expanded(child: identity),
                        ],
                      )
                    else ...[
                      selector,
                      SizedBox(height: SimSpace.ms),
                      identity,
                    ],
                    SizedBox(height: SimSpace.ms),
                    actions,
                  ],
                );
              },
            ),
            if (runtime.details.isNotEmpty) ...[
              SizedBox(height: SimSpace.ms),
              SimNotice(
                text: '${tr('sim.connection_details')}\n${runtime.details}',
                error: runtime.phase == ConnectionPhase.failed,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _position(
    BuildContext context,
    TerminalRuntime runtime,
    DriveRoute? route,
  ) {
    final fix = runtime.location;
    final preview = RoutePreview(route: route, location: fix, height: 160);
    return SimPanel(
      title: tr('sim.current_position'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SimSpace.lg,
            runSpacing: SimSpace.ms,
            children: [
              _reading(
                context,
                tr('sim.coordinates'),
                '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}',
              ),
              _reading(
                context,
                tr('sim.field.speed'),
                fix.speed.toStringAsFixed(1),
              ),
              _reading(context, tr('sim.field.direction'), '${fix.direction}°'),
            ],
          ),
          SizedBox(height: SimSpace.ms),
          Text(
            tr(
              'sim.last_sent_value',
              namedArgs: {
                'time': runtime.lastSent == null
                    ? tr('sim.not_sent')
                    : simTime(runtime.lastSent!),
              },
            ),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (route != null) ...[
            SizedBox(height: SimSpace.ms),
            preview,
          ] else
            SimExpansion(
              title: Text(
                tr('sim.map_preview'),
                style: context.textTheme.bodySmall,
              ),
              tilePadding: EdgeInsets.zero,
              children: [preview],
            ),
        ],
      ),
    );
  }

  Widget _reading(BuildContext context, String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      SizedBox(height: SimSpace.xs),
      Text(value, style: simCodeStyle(context)),
    ],
  );

  Widget _task(BuildContext context, DriveTask? task) {
    final c = controller;
    return SimPanel(
      title: tr('sim.current_task'),
      child: task == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('sim.no_assigned_task'),
                  style: context.textTheme.bodyMedium,
                ),
                SizedBox(height: SimSpace.xs),
                Text(
                  tr('sim.manual_mode_hint'),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: SimSpace.ms),
                SimButton(
                  label: tr('sim.manage_routes_tasks'),
                  onPressed: () => onNavigate(2),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall,
                      ),
                    ),
                    TaskStatus(controller: c, task: task),
                  ],
                ),
                SizedBox(height: SimSpace.xs),
                Text(
                  c.route(task.routeId).name,
                  style: context.textTheme.bodySmall,
                ),
                SizedBox(height: SimSpace.ms),
                ShadProgress(
                  minHeight: 3,
                  value: c.taskRuntimes[task.id]?.player.progress ?? 0,
                ),
                SizedBox(height: SimSpace.ms),
                Text(
                  tr(
                    'sim.task_progress',
                    namedArgs: {
                      'percent':
                          ((c.taskRuntimes[task.id]?.player.progress ?? 0) *
                                  100)
                              .toStringAsFixed(1),
                      'distance':
                          (c.taskRuntimes[task.id]?.player.travelledKm ?? 0)
                              .toStringAsFixed(2),
                    },
                  ),
                  style: simNumberStyle(context),
                ),
                SizedBox(height: SimSpace.ms),
                TaskControls(controller: c, task: task),
              ],
            ),
    );
  }

  Widget _logs(BuildContext context, List<ProtocolLog> logs) => SimPanel(
    title: tr('sim.latest_logs'),
    trailing: SimTextButton(
      onPressed: () => onNavigate(3),
      child: Text(tr('sim.view_all')),
    ),
    child: logs.isEmpty
        ? Text(
            tr('sim.no_logs_hint'),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          )
        : Column(
            children: [
              for (final log in logs)
                SimListRow(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    log.isError
                        ? Icons.error_outline
                        : log.direction == LogDirection.received
                        ? Icons.south_west
                        : log.direction == LogDirection.sent
                        ? Icons.north_east
                        : Icons.info_outline,
                    color: log.isError
                        ? context.colors.error
                        : context.colors.onSurfaceVariant,
                    size: 14,
                  ),
                  title: Text(
                    '${log.idHex}  ${log.message}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    simTime(log.time),
                    style: simCodeStyle(context),
                  ),
                  onTap: () => showLogDetail(context, controller, log),
                ),
            ],
          ),
  );
}

class _Statistics extends StatelessWidget {
  const _Statistics({required this.controller});
  final SimulatorController controller;
  @override
  Widget build(BuildContext context) {
    final readings = [
      (
        tr('sim.online_terminals'),
        '${controller.onlineCount} / ${controller.terminals.length}',
      ),
      (tr('sim.running_tasks'), '${controller.runningCount}'),
      (tr('sim.messages_sent'), '${controller.sentCount}'),
      (tr('sim.messages_received'), '${controller.receivedCount}'),
    ];
    return SimPanel(
      key: const ValueKey('console-statistics'),
      padding: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 560 ? 2 : 4;
          return Wrap(
            children: [
              for (var i = 0; i < readings.length; i++)
                Container(
                  width: constraints.maxWidth / columns,
                  padding: EdgeInsets.all(SimSpace.lg),
                  decoration: BoxDecoration(
                    border: Border(
                      right: i % columns < columns - 1
                          ? BorderSide(color: context.colors.outlineVariant)
                          : BorderSide.none,
                      bottom: i < readings.length - columns
                          ? BorderSide(color: context.colors.outlineVariant)
                          : BorderSide.none,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        readings[i].$1,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: SimSpace.md),
                      Text(
                        readings[i].$2,
                        style: context.textTheme.headlineLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
