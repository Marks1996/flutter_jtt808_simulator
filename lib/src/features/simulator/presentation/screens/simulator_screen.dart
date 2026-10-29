import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/desktop_window_service.dart';
import '../../../../shared/app_assets.dart';
import '../../../../shared/widgets/desktop_window_frame.dart';
import '../providers/simulator_provider.dart';
import '../widgets/sim_ui.dart';
import 'console_page.dart';
import 'protocol_logs_page.dart';
import 'routes_tasks_page.dart';
import 'settings_page.dart';
import 'terminals_page.dart';

/// One navigation frame and one work surface. Content is sized by its records,
/// not stretched into a dashboard of empty panels.
class SimulatorScreen extends ConsumerStatefulWidget {
  const SimulatorScreen({super.key});
  @override
  ConsumerState<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends ConsumerState<SimulatorScreen> {
  int _page = 0;
  String? _terminalId;
  static const _nav = [
    ('console', 'assets/icons/navigation/board_24_color.svg'),
    ('terminals', 'assets/icons/navigation/phone_laptop_24_color.svg'),
    ('routes_tasks', 'assets/icons/navigation/location_ripple_24_color.svg'),
    ('protocol_logs', 'assets/icons/navigation/code_block_24_color.svg'),
    (
      'settings',
      'assets/icons/navigation/arrow_clockwise_dashes_settings_24_color.svg',
    ),
  ];

  void _navigate(int index) => setState(() => _page = index);

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(simulatorProvider);
    final terminalId = c.terminals.any((t) => t.id == _terminalId)
        ? _terminalId
        : c.terminals.firstOrNull?.id;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = DesktopWindowService.isSupported;
        final navigation = desktop || constraints.maxWidth >= 640;
        final rail = !desktop && constraints.maxWidth < 960;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.saveState.isFailure)
              Padding(
                padding: EdgeInsets.all(SimSpace.md),
                child: SimNotice(
                  key: const ValueKey('save-failure-banner'),
                  text: tr('sim.save_failure'),
                  error: true,
                  action: SimTextButton(
                    onPressed: c.retrySave,
                    child: Text(tr('sim.retry_save')),
                  ),
                ),
              ),
            Expanded(child: _content(context, c, terminalId)),
          ],
        );
        final work = SafeArea(
          bottom: false,
          child: Padding(
            padding: navigation
                ? const EdgeInsets.only(right: 8, bottom: 8)
                : EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: navigation
                  ? SimStyle.sheetRadius
                  : BorderRadius.zero,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLowest,
                  borderRadius: navigation ? SimStyle.sheetRadius : null,
                  border: navigation
                      ? Border.all(color: context.colors.outlineVariant)
                      : null,
                ),
                child: content,
              ),
            ),
          ),
        );
        return Scaffold(
          backgroundColor: context.colors.surface,
          appBar: navigation || DesktopWindowService.isSupported
              ? null
              : AppBar(
                  centerTitle: false,
                  toolbarHeight: 44,
                  title: Row(
                    children: [
                      ClipRRect(
                        borderRadius: AppBorders.sm,
                        child: Image.asset(
                          AppAssets.logo,
                          width: 28,
                          height: 28,
                          excludeFromSemantics: true,
                        ),
                      ),
                      SizedBox(width: SimSpace.sm),
                      Flexible(
                        child: Text(
                          tr('sim.app_name'),
                          style: context.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
          body: navigation
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sidebar(context, c, collapsed: rail),
                    Expanded(child: work),
                  ],
                )
              : work,
          bottomNavigationBar: navigation ? null : _bottomNavigation(context),
        );
      },
    );
  }

  Widget _bottomNavigation(BuildContext context) => DecoratedBox(
    key: const ValueKey('sim-bottom-navigation'),
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(top: BorderSide(color: context.colors.outlineVariant)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            for (var i = 0; i < _nav.length; i++)
              Expanded(
                child: Semantics(
                  selected: _page == i,
                  child: ShadButton.ghost(
                    key: ValueKey('nav-${_nav[i].$1}'),
                    height: 52,
                    expands: true,
                    padding: EdgeInsets.zero,
                    foregroundColor: _page == i
                        ? context.colors.onSurface
                        : context.colors.onSurfaceVariant,
                    onPressed: () => _navigate(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          _nav[i].$2,
                          width: 22,
                          height: 22,
                          excludeFromSemantics: true,
                        ),
                        SizedBox(height: SimSpace.xs),
                        Text(
                          tr('sim.nav.${_nav[i].$1}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelSmall?.copyWith(
                            fontWeight: _page == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _sidebar(
    BuildContext context,
    SimulatorController c, {
    required bool collapsed,
  }) {
    Widget item(int i) {
      final selected = _page == i;
      final button = Semantics(
        selected: selected,
        label: collapsed ? tr('sim.${_nav[i].$1}') : null,
        child: ShadButton.ghost(
          key: ValueKey('nav-${_nav[i].$1}'),
          height: 34,
          expands: !collapsed,
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          padding: EdgeInsets.symmetric(horizontal: SimSpace.ms),
          backgroundColor: selected
              ? context.colors.surfaceContainerHigh
              : null,
          foregroundColor: selected
              ? context.colors.onSurface
              : context.colors.onSurfaceVariant,
          leading: SvgPicture.asset(
            _nav[i].$2,
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
          onPressed: () => _navigate(i),
          child: collapsed
              ? null
              : Text(
                  tr('sim.${_nav[i].$1}'),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
        ),
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 6 : 8,
          vertical: 2,
        ),
        child: collapsed
            ? ShadTooltip(
                builder: (_) => Text(tr('sim.${_nav[i].$1}')),
                child: button,
              )
            : button,
      );
    }

    return SizedBox(
      key: ValueKey(
        collapsed ? 'sim-navigation-rail' : 'sim-labeled-navigation',
      ),
      width: collapsed ? 56 : 184,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder(
              valueListenable: debugWindowStyle,
              builder: (context, value, child) =>
                  DesktopWindowService.isSupported &&
                      windowStyle == TargetPlatform.windows
                  ? SizedBox(height: SimSpace.xs)
                  : child!,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 16,
                  12,
                  collapsed ? 8 : 12,
                  18,
                ),
                child: collapsed
                    ? ShadTooltip(
                        builder: (_) => Text(tr('sim.app_name')),
                        child: ClipRRect(
                          borderRadius: AppBorders.sm,
                          child: Image.asset(
                            AppAssets.logo,
                            width: 32,
                            height: 32,
                            excludeFromSemantics: true,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          ClipRRect(
                            borderRadius: AppBorders.sm,
                            child: Image.asset(
                              AppAssets.logo,
                              width: 32,
                              height: 32,
                              excludeFromSemantics: true,
                            ),
                          ),
                          SizedBox(width: SimSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('sim.app_name'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.titleMedium,
                                ),
                                SizedBox(height: SimSpace.xs),
                                Text(
                                  tr('sim.local_workspace'),
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            for (var i = 0; i < _nav.length - 1; i++) item(i),
            const Spacer(),
            item(_nav.length - 1),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('sim.protocol_short'),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: SimSpace.xs),
                    Text(
                      tr(
                        c.saveState.isLoading
                            ? 'sim.saving'
                            : c.saveState.isFailure
                            ? 'sim.unsaved_workspace'
                            : 'sim.saved_locally',
                      ),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: c.saveState.isFailure
                            ? context.colors.error
                            : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    SimulatorController c,
    String? terminalId,
  ) {
    if (c.loadState.isLoading || c.loadState.isInitial) {
      return Center(
        child: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ShadProgress(minHeight: 3),
              SizedBox(height: SimSpace.md),
              Text(tr('sim.loading_workspace')),
            ],
          ),
        ),
      );
    }
    if (c.loadState.isFailure) {
      return SingleChildScrollView(
        child: SimEmpty(
          key: const ValueKey('load-failure'),
          title: tr('sim.load_failure'),
          message: tr('sim.load_failure_recovery'),
          icon: Icons.folder_off_outlined,
          action: SimButton(
            label: tr('sim.retry_load'),
            primary: true,
            icon: Icons.refresh,
            onPressed: c.load,
          ),
        ),
      );
    }
    void select(String? id) => setState(() => _terminalId = id);
    return switch (_page) {
      0 => ConsolePage(
        controller: c,
        terminalId: terminalId,
        onTerminalChanged: select,
        onNavigate: _navigate,
      ),
      1 => TerminalsPage(
        controller: c,
        onOpenTerminal: (id) => setState(() {
          _terminalId = id;
          _page = 0;
        }),
      ),
      2 => RoutesTasksPage(controller: c),
      3 => ProtocolLogsPage(
        controller: c,
        terminalId: terminalId,
        onTerminalChanged: select,
      ),
      _ => SettingsPage(controller: c),
    };
  }
}
