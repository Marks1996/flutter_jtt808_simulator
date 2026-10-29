import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../extensions/context_extension.dart';
import '../../services/desktop_window_service.dart';
import '../app_assets.dart';
import '../../theme/theme_constants.dart';
import '../../utils/async_state.dart';
import '../../utils/failure.dart';
import '../../utils/logger.dart';
import '../../utils/platform_info.dart';

/// Debug visual override; native operations always use the host OS.
final debugWindowStyle = ValueNotifier<TargetPlatform?>(null);
TargetPlatform get windowStyle =>
    (kDebugMode ? debugWindowStyle.value : null) ?? defaultTargetPlatform;

/// Application-wide native chrome, independent of responsive content width.
/// The local overlay lets title-bar tooltips work above the router's navigator.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _listening = false;
  bool _focused = true;
  bool _maximized = false;
  bool _fullScreen = false;
  RequestState<void> _operation = const RequestInitial();

  @override
  void initState() {
    super.initState();
    if (DesktopWindowService.isSupported) {
      windowManager.addListener(this);
      _listening = true;
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    if (_listening) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait([
        windowManager.isMaximized(),
        windowManager.isFullScreen(),
        if (PlatformInfo.isLinux)
          Future.value(true)
        else
          windowManager.isFocused(),
      ]);
      if (!mounted) return;
      setState(() {
        _maximized = values[0];
        _fullScreen = values[1];
        _focused = values[2];
      });
    } catch (error, stack) {
      AppLogger.error(
        'Could not read native window state',
        error: error,
        stackTrace: stack,
        category: LogCategory.app,
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_operation.isLoading) return;
    setState(() => _operation = const RequestLoading());
    try {
      await action();
      if (mounted) setState(() => _operation = const RequestSuccess(null));
    } catch (error, stack) {
      AppLogger.error(
        'Desktop window action failed',
        error: error,
        stackTrace: stack,
        category: LogCategory.app,
      );
      if (!mounted) return;
      final message = tr('window.action_failed');
      setState(
        () =>
            _operation = RequestFailure(UnknownFailure(message, error: error)),
      );
      ShadToaster.of(
        context,
      ).show(ShadToast.destructive(description: Text(message)));
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    } else if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refresh();
  }

  @override
  void onWindowFocus() {
    if (mounted) setState(() => _focused = true);
  }

  @override
  void onWindowBlur() {
    if (mounted) setState(() => _focused = false);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowResized() => unawaited(_refresh());
  @override
  void onWindowRestore() => unawaited(_refresh());
  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: debugWindowStyle,
    builder: (context, value, child) => _buildFrame(context),
  );
  Widget _buildFrame(BuildContext context) {
    if (!DesktopWindowService.isSupported) return widget.child;
    final expanded = _maximized || _fullScreen;
    if (PlatformInfo.isMacOS && windowStyle == TargetPlatform.macOS) {
      // Hidden-inset style (reference: cursor-byok's MacTitleBarHiddenInset
      // window): the content fills the whole window, the native traffic lights
      // float above it, and an invisible strip along the top carries the drag
      // gesture. Content is pushed down via MediaQuery padding so nothing sits
      // under the traffic lights.
      final mediaQuery = MediaQuery.of(context);
      final content = MediaQuery(
        data: mediaQuery.copyWith(
          padding: mediaQuery.padding + const EdgeInsets.only(top: _barHeight),
        ),
        child: widget.child,
      );
      final frame = DecoratedBox(
        decoration: BoxDecoration(
          border: expanded
              ? null
              : Border.all(color: context.colors.outlineVariant),
        ),
        child: Padding(
          padding: expanded ? EdgeInsets.zero : const EdgeInsets.all(1),
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _barHeight,
                child: _MacTitleDragStrip(
                  enabled: !_operation.isLoading,
                  onDrag: () => _run(windowManager.startDragging),
                  onToggleMaximize: () => _run(_toggleMaximize),
                ),
              ),
            ],
          ),
        ),
      );
      // AppKit keeps native resize hit testing. startResizing is a Linux/Windows
      // API, so a Flutter resize overlay must not intercept macOS edges.
      return Overlay.wrap(child: frame);
    }
    final frame = Material(
      color: context.colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: expanded
              ? null
              : Border.all(color: context.colors.outlineVariant),
        ),
        child: Padding(
          padding: expanded ? EdgeInsets.zero : const EdgeInsets.all(1),
          child: Column(
            children: [
              DesktopWindowBar(
                macStyle: windowStyle == TargetPlatform.macOS,
                focused: _focused,
                maximized: _maximized,
                fullScreen: _fullScreen,
                enabled: !_operation.isLoading,
                onDrag: () => _run(windowManager.startDragging),
                onToggleMaximize: () => _run(_toggleMaximize),
                onMinimize: () => _run(windowManager.minimize),
                onClose: () => _run(windowManager.close),
              ),
              Expanded(child: Semantics(container: true, child: widget.child)),
            ],
          ),
        ),
      ),
    );
    return Overlay.wrap(
      child: DragToResizeArea(
        resizeEdgeSize: AppSpacing.xs,
        enableResizeEdges: expanded ? const [] : null,
        child: frame,
      ),
    );
  }
}

/// Height of the invisible macOS title-bar strip. Matches the traffic-light
/// span plus breathing room; see also the Windows/Linux bar height below.
const double _barHeight = 32;

/// Invisible full-width strip that turns the top of the macOS window into a
/// drag surface without painting anything over the content.
class _MacTitleDragStrip extends StatelessWidget {
  const _MacTitleDragStrip({
    required this.onDrag,
    required this.onToggleMaximize,
    this.enabled = true,
  });

  final VoidCallback onDrag, onToggleMaximize;
  final bool enabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('window-drag-area'),
    behavior: HitTestBehavior.opaque,
    onPanStart: enabled ? (_) => onDrag() : null,
    onDoubleTap: enabled ? onToggleMaximize : null,
  );
}

/// Flat shadcn-style caption bar for Windows/Linux: one draggable area and
/// separate ghost controls. macOS never renders this widget; its chrome is the
/// native traffic lights plus the invisible strip above.
class DesktopWindowBar extends StatelessWidget {
  const DesktopWindowBar({
    super.key,
    required this.onDrag,
    required this.onToggleMaximize,
    required this.onMinimize,
    required this.onClose,
    this.macStyle = false,
    this.focused = true,
    this.maximized = false,
    this.fullScreen = false,
    this.enabled = true,
  });

  final VoidCallback onDrag, onToggleMaximize, onMinimize, onClose;
  final bool focused, maximized, fullScreen, enabled;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = focused ? colors.onSurface : colors.onSurfaceVariant;
    return SizedBox(
      key: const ValueKey('desktop-window-bar'),
      child: SizedBox(
        height: AppSpacing.xl,
        child: Row(
          children: [
            SizedBox(width: AppSpacing.sm),
            if (macStyle) ...[
              for (final control in [
                (tr('window.close'), colors.error, onClose),
                (tr('window.minimize'), context.appColors.warning, onMinimize),
                (
                  tr('window.maximize'),
                  context.appColors.success,
                  onToggleMaximize,
                ),
              ])
                Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: ShadTooltip(
                    builder: (_) => Text(control.$1),
                    child: Semantics(
                      label: control.$1,
                      button: true,
                      child: ShadButton.ghost(
                        width: AppSpacing.ml,
                        height: AppSpacing.lg,
                        padding: EdgeInsets.zero,
                        enabled: enabled,
                        onPressed: control.$3,
                        child: Container(
                          width: AppSpacing.ms,
                          height: AppSpacing.ms,
                          decoration: BoxDecoration(
                            color: control.$2,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            Expanded(
              child: GestureDetector(
                key: const ValueKey('window-drag-area'),
                behavior: HitTestBehavior.opaque,
                onPanStart: enabled ? (_) => onDrag() : null,
                onDoubleTap: enabled ? onToggleMaximize : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        if (!macStyle)
                          Image.asset(
                            AppAssets.logo,
                            width: 20,
                            height: 20,
                            excludeFromSemantics: true,
                          ),
                        SizedBox(width: AppSpacing.sm),
                        if (!macStyle)
                          Flexible(
                            child: Text(
                              tr('sim.app_name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: foreground,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!macStyle)
              _WindowButton(
                key: const ValueKey('window-minimize'),
                label: tr('window.minimize'),
                icon: Icons.remove_rounded,
                onPressed: enabled ? onMinimize : null,
              ),
            if (!macStyle)
              _WindowButton(
                key: const ValueKey('window-maximize'),
                label: tr(
                  fullScreen
                      ? 'window.exit_fullscreen'
                      : maximized
                      ? 'window.restore'
                      : 'window.maximize',
                ),
                icon: fullScreen
                    ? Icons.fullscreen_exit_rounded
                    : maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                onPressed: enabled ? onToggleMaximize : null,
              ),
            if (!macStyle)
              _WindowButton(
                key: const ValueKey('window-close'),
                label: tr('window.close'),
                icon: Icons.close_rounded,
                destructive: true,
                onPressed: enabled ? onClose : null,
              ),
            SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => ShadTooltip(
    builder: (_) => Text(label),
    child: Semantics(
      container: true,
      label: label,
      child: ShadButton.ghost(
        width: AppSpacing.xl + AppSpacing.sm,
        height: AppSpacing.xl,
        padding: EdgeInsets.zero,
        enabled: onPressed != null,
        onPressed: onPressed,
        foregroundColor: context.colors.onSurfaceVariant,
        hoverBackgroundColor: destructive
            ? context.colors.error
            : context.colors.surfaceContainerHighest,
        hoverForegroundColor: destructive
            ? context.colors.onError
            : context.colors.onSurface,
        child: Icon(icon, size: 16),
      ),
    ),
  );
}
