import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

class TaskStatus extends StatelessWidget {
  const TaskStatus({super.key, required this.controller, required this.task});
  final SimulatorController controller;
  final DriveTask task;

  @override
  Widget build(BuildContext context) {
    final phase = controller.taskRuntimes[task.id]?.phase ?? TaskPhase.stopped;
    final online =
        controller.runtime(task.terminalId).phase == ConnectionPhase.online;
    final waiting = phase == TaskPhase.running && !online;
    return Text(
      tr(waiting ? 'sim.task_waiting' : 'sim.task_phase.${phase.name}'),
      style: context.textTheme.labelMedium?.copyWith(
        color: waiting || phase == TaskPhase.paused
            ? context.appColors.warning
            : phase == TaskPhase.running
            ? context.appColors.success
            : context.colors.onSurfaceVariant,
      ),
    );
  }
}

class TaskControls extends StatelessWidget {
  const TaskControls({super.key, required this.controller, required this.task});
  final SimulatorController controller;
  final DriveTask task;

  @override
  Widget build(BuildContext context) {
    final phase = controller.taskRuntimes[task.id]?.phase ?? TaskPhase.stopped;
    final runtime = controller.runtime(task.terminalId);
    return Wrap(
      spacing: SimSpace.sm,
      runSpacing: SimSpace.sm,
      children: [
        if (phase == TaskPhase.running)
          SimButton(
            label: tr('sim.pause_task'),
            icon: Icons.pause,
            onPressed: () => controller.pauseTask(task.id),
          )
        else
          SimButton(
            label: tr(
              phase == TaskPhase.paused ? 'sim.resume_task' : 'sim.start_task',
            ),
            icon: Icons.play_arrow,
            primary: true,
            onPressed: () =>
                simRun(context, () => controller.startTask(task.id)),
          ),
        if (phase == TaskPhase.running && !runtime.busy)
          SimButton(
            label: tr('sim.reconnect'),
            icon: Icons.refresh,
            onPressed: () =>
                simRun(context, () => controller.connect(task.terminalId)),
          ),
        SimButton(
          label: tr('sim.stop_task'),
          icon: Icons.stop_outlined,
          onPressed: phase == TaskPhase.running || phase == TaskPhase.paused
              ? () => controller.stopTask(task.id)
              : null,
        ),
      ],
    );
  }
}
