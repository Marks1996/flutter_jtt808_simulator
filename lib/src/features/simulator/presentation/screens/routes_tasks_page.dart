import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../services/desktop_window_service.dart';
import '../providers/simulator_provider.dart';
import '../widgets/route_editor.dart';
import '../widgets/route_preview.dart';
import '../widgets/sim_ui.dart';
import '../widgets/task_controls.dart';
import '../widgets/task_editor.dart';

class RoutesTasksPage extends StatefulWidget {
  const RoutesTasksPage({super.key, required this.controller});
  final SimulatorController controller;

  @override
  State<RoutesTasksPage> createState() => _RoutesTasksPageState();
}

class _RoutesTasksPageState extends State<RoutesTasksPage> {
  int _section = 0;
  String? _routeId;
  bool _previewExpanded = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final canCreateTask = c.terminals.isNotEmpty && c.routes.isNotEmpty;
    return SimPage(
      title: tr('sim.routes_tasks'),
      subtitle: tr('sim.routes_tasks_subtitle'),
      actions: [
        SimButton(
          label: tr('sim.create_route'),
          icon: Icons.add,
          onPressed: () => showRouteEditor(context, c),
        ),
        ShadTooltip(
          builder: (_) => Text(
            tr(
              canCreateTask
                  ? 'sim.create_task'
                  : 'sim.errors.task_dependencies',
            ),
          ),
          child: SimButton(
            label: tr('sim.create_task'),
            primary: true,
            icon: Icons.add,
            onPressed: canCreateTask ? () => showTaskEditor(context, c) : null,
          ),
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (DesktopWindowService.isSupported ||
                constraints.maxWidth >= 800) {
              // Both regions keep their own content height; neither empty list
              // stretches to match its neighbour's preview or playback controls.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _routes(context)),
                  const SizedBox(width: 20),
                  Expanded(flex: 6, child: _tasks(context)),
                ],
              );
            }
            return ShadTabs<int>(
              value: _section,
              onChanged: (value) => setState(() => _section = value),
              tabs: [
                ShadTab(
                  value: 0,
                  content: _routes(context),
                  child: Text(tr('sim.routes')),
                ),
                ShadTab(
                  value: 1,
                  content: _tasks(context),
                  child: Text(tr('sim.tasks')),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _routes(BuildContext context) {
    final c = widget.controller;
    final route =
        c.routes.where((route) => route.id == _routeId).firstOrNull ??
        c.routes.firstOrNull;
    return SimPanel(
      title: tr('sim.routes_count', namedArgs: {'count': '${c.routes.length}'}),
      child: c.routes.isEmpty
          ? SimEmpty(
              title: tr('sim.no_routes'),
              message: tr('sim.no_routes_hint'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in c.routes)
                  _routeRow(context, item, selected: item.id == route?.id),
                if (route != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          height:
                              DesktopWindowService.isSupported ||
                                  MediaQuery.sizeOf(context).width >= 600
                              ? 32
                              : 44,
                          mainAxisAlignment: MainAxisAlignment.start,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(
                            _previewExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.chevron_right,
                            size: 18,
                          ),
                          onPressed: () => setState(
                            () => _previewExpanded = !_previewExpanded,
                          ),
                          child: const Text('WGS84'),
                        ),
                      ),
                      SimButton(
                        label: tr('sim.copy_csv'),
                        icon: Icons.copy_outlined,
                        onPressed: () =>
                            simCopy(context, RouteCsv.encode(route)),
                      ),
                    ],
                  ),
                  if (_previewExpanded) ...[
                    const SizedBox(height: 8),
                    RoutePreview(
                      key: ValueKey(route.id),
                      route: route,
                      height: 180,
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _routeRow(
    BuildContext context,
    DriveRoute route, {
    required bool selected,
  }) {
    final busy = _routeBusy(route.id);
    final inUse = widget.controller.tasks.any((t) => t.routeId == route.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? context.colors.surfaceContainerHigh : null,
        borderRadius: AppBorders.input,
      ),
      child: SimListRow(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        title: Text(
          route.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Text(
          tr(
            'sim.route_summary',
            namedArgs: {
              'points': '${route.points.length}',
              'distance': route.distanceKm.toStringAsFixed(2),
            },
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: simNumberStyle(
            context,
          )?.copyWith(fontSize: 12, color: context.colors.onSurfaceVariant),
        ),
        onTap: () => setState(() => _routeId = route.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SimIconButton(
              tooltip: tr(
                busy ? 'sim.errors.stop_before_edit' : 'sim.edit_route',
              ),
              onPressed: busy
                  ? null
                  : () => showRouteEditor(context, widget.controller, route),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            SimIconButton(
              tooltip: tr(
                inUse ? 'sim.errors.route_in_use' : 'sim.delete_route',
              ),
              onPressed: inUse ? null : () => _deleteRoute(context, route),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  bool _routeBusy(String routeId) => widget.controller.tasks.any(
    (task) =>
        task.routeId == routeId &&
        [
          TaskPhase.running,
          TaskPhase.paused,
        ].contains(widget.controller.taskRuntimes[task.id]?.phase),
  );

  Future<void> _deleteRoute(BuildContext context, DriveRoute route) async {
    if (await simConfirm(
          context,
          title: tr('sim.delete_route'),
          body: tr('sim.delete_named', namedArgs: {'name': route.name}),
          destructive: true,
        ) &&
        context.mounted) {
      await simRun(context, () => widget.controller.deleteRoute(route.id));
    }
  }

  Widget _tasks(BuildContext context) {
    final c = widget.controller;
    return SimPanel(
      title: tr('sim.tasks_count', namedArgs: {'count': '${c.tasks.length}'}),
      child: c.tasks.isEmpty
          ? SimEmpty(
              title: tr('sim.no_tasks'),
              message: tr(
                c.terminals.isEmpty || c.routes.isEmpty
                    ? 'sim.no_tasks_dependencies'
                    : 'sim.no_tasks_hint',
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < c.tasks.length; i++) ...[
                  if (i > 0)
                    const ShadSeparator.horizontal(
                      margin: EdgeInsets.symmetric(vertical: 12),
                    ),
                  _task(context, c.tasks[i]),
                ],
                const SizedBox(height: 12),
                Text(
                  tr('sim.playback_help'),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _task(BuildContext context, DriveTask task) {
    final c = widget.controller;
    final runtime = c.taskRuntimes[task.id];
    final terminal = c.terminal(task.terminalId);
    final route = c.route(task.routeId);
    final metadata =
        '${terminal.name} · ${route.name} · '
        '${tr(task.loop ? 'sim.loop_enabled' : 'sim.single_pass')}';
    final progress = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadProgress(
          value: runtime?.player.progress ?? 0,
          minHeight: 4,
          color: context.colors.primary,
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'sim.task_progress',
            namedArgs: {
              'percent': ((runtime?.player.progress ?? 0) * 100)
                  .toStringAsFixed(1),
              'distance': (runtime?.player.travelledKm ?? 0).toStringAsFixed(2),
            },
          ),
          style: simNumberStyle(context)?.copyWith(fontSize: 12),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: TaskStatus(controller: c, task: task),
            ),
            const SizedBox(width: 4),
            _taskMenu(context, task),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: ShadTooltip(
                builder: (_) => Text(metadata),
                child: Text(
                  metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SimPhase(c.runtime(terminal.id).phase),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 560) {
              return Row(
                children: [
                  Expanded(child: progress),
                  const SizedBox(width: 16),
                  TaskControls(controller: c, task: task),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                progress,
                const SizedBox(height: 8),
                TaskControls(controller: c, task: task),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _taskMenu(BuildContext context, DriveTask task) {
    final c = widget.controller;
    final phase = c.taskRuntimes[task.id]?.phase ?? TaskPhase.stopped;
    final busy = phase == TaskPhase.running || phase == TaskPhase.paused;
    final controlSize =
        DesktopWindowService.isSupported ||
            MediaQuery.sizeOf(context).width >= 600
        ? 32.0
        : 44.0;
    return ShadTooltip(
      builder: (_) => Text(tr('sim.actions')),
      child: ShadMenubar(
        padding: EdgeInsets.zero,
        border: ShadBorder.none,
        items: [
          ShadMenubarItem(
            height: controlSize,
            width: controlSize,
            buttonPadding: EdgeInsets.zero,
            anchor: const ShadAnchorAuto(
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: Offset(0, 4),
            ),
            items: [
              ShadContextMenuItem(
                enabled: !busy,
                onPressed: () => showTaskEditor(context, c, task),
                child: Text(tr('sim.edit_task')),
              ),
              ShadContextMenuItem(
                onPressed: () async {
                  if (await simConfirm(
                        context,
                        title: tr('sim.delete_task'),
                        body: tr(
                          'sim.delete_named',
                          namedArgs: {'name': task.name},
                        ),
                        destructive: true,
                      ) &&
                      context.mounted) {
                    await simRun(context, () => c.deleteTask(task.id));
                  }
                },
                child: Text(tr('sim.delete_task')),
              ),
            ],
            child: Semantics(
              label: tr('sim.actions'),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: Icon(Icons.more_horiz, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
