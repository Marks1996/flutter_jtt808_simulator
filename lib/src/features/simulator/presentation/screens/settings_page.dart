import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/simulator_provider.dart';
import '../widgets/sim_ui.dart';
import '../widgets/workspace_transfer_dialog.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final SimulatorController controller;

  @override
  Widget build(BuildContext context) => SimPage(
    title: tr('sim.settings'),
    subtitle: '',
    maxWidth: 960,
    children: [
      _SettingsSection(
        title: tr('sim.appearance_language'),
        first: true,
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: SimSpace.lg,
            runSpacing: SimSpace.md,
            children: [
              SizedBox(
                width: constraints.maxWidth.clamp(0, 220).toDouble(),
                child: SimSelect<String>(
                  label: tr('sim.theme'),
                  value: controller.workspace.theme,
                  items: [
                    for (final mode in ['system', 'light', 'dark'])
                      SimOption(
                        value: mode,
                        child: Text(tr('sim.theme_mode.$mode')),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      simRun(context, () => controller.setTheme(value));
                    }
                  },
                ),
              ),
              SizedBox(
                width: constraints.maxWidth.clamp(0, 200).toDouble(),
                child: SimSelect<String>(
                  label: tr('sim.language'),
                  value: context.locale.languageCode,
                  items: [
                    for (final language in ['zh', 'en'])
                      SimOption(
                        value: language,
                        child: Text(tr('sim.language_name.$language')),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      simRun(context, () => context.setLocale(Locale(value)));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      _SettingsSection(
        title: tr('sim.workspace'),
        description: tr('sim.workspace_help'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('sim.workspace_contents'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: SimSpace.xs),
            Text(
              tr(
                'sim.workspace_counts',
                namedArgs: {
                  'terminals': '${controller.terminals.length}',
                  'routes': '${controller.routes.length}',
                  'tasks': '${controller.tasks.length}',
                },
              ),
              style: simNumberStyle(context),
            ),
            SizedBox(height: SimSpace.md),
            Wrap(
              spacing: SimSpace.ms,
              runSpacing: SimSpace.ms,
              children: [
                SimButton(
                  label: tr('sim.export_workspace'),
                  icon: Icons.download_outlined,
                  onPressed: () => showWorkspaceTransfer(
                    context,
                    controller,
                    importing: false,
                  ),
                ),
                SimButton(
                  label: tr('sim.import_workspace'),
                  icon: Icons.upload_file_outlined,
                  onPressed: () => showWorkspaceTransfer(
                    context,
                    controller,
                    importing: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: SimSpace.md),
            Text(
              tr('sim.workspace_secret_warning'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      _SettingsSection(
        title: tr('sim.support_scope'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('sim.support_scope_body'),
              style: context.textTheme.bodyMedium,
            ),
            SizedBox(height: SimSpace.ms),
            Text(
              tr('sim.unsupported_scope'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      _SettingsSection(
        title: tr('sim.coordinate_policy'),
        child: Text(
          tr('sim.coordinate_policy_body'),
          style: context.textTheme.bodyMedium,
        ),
      ),
      _SettingsSection(
        title: tr('sim.references'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _link(
              context,
              'reference_jtt808',
              'https://github.com/SmallChi/JT808',
            ),
            _link(
              context,
              'reference_protocol',
              'https://github.com/glaciall/jtt808-simulator',
            ),
            _link(
              context,
              'reference_osm',
              'https://www.openstreetmap.org/copyright',
            ),
            SizedBox(height: SimSpace.ms),
            Text(
              tr('sim.reference_disclaimer'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _link(BuildContext context, String key, String url) =>
      ShadButton.ghost(
        height: 0,
        expands: true,
        mainAxisAlignment: MainAxisAlignment.start,
        padding: EdgeInsets.symmetric(vertical: SimSpace.ms),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(tr('sim.$key'))),
            SizedBox(width: SimSpace.ms),
            Icon(
              Icons.open_in_new,
              size: 14,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
        onPressed: () => simRun(context, () async {
          if (!await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          )) {
            throw StateError('Unable to open reference');
          }
        }),
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    this.description,
    this.first = false,
  });

  final String title;
  final String? description;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(
      top: first ? SimSpace.ms : SimSpace.xl,
      bottom: SimSpace.ms,
    ),
    decoration: BoxDecoration(
      border: first
          ? null
          : Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description != null) ...[
              SizedBox(height: SimSpace.ms),
              Text(
                description!,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: child,
        );
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              SizedBox(height: SimSpace.md),
              content,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 240, child: label),
            SizedBox(width: SimSpace.xl),
            Expanded(
              child: Align(alignment: Alignment.topLeft, child: content),
            ),
          ],
        );
      },
    ),
  );
}
