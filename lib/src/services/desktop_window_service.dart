import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/platform_info.dart';

/// Native window setup only. Phone/tablet layouts never invoke desktop plugins.
class DesktopWindowService {
  DesktopWindowService._();
  static final instance = DesktopWindowService._();
  static const minimumSize = Size(1100, 720);
  static const initialSize = minimumSize;

  static bool get isSupported => !kIsWeb && PlatformInfo.isDesktop;

  Future<void> initialize() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    final useNativeTitleBar = PlatformInfo.isMacOS;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'JT/T808 模拟器',
        size: initialSize,
        minimumSize: minimumSize,
        center: true,
        // macOS keeps its native traffic lights over the Flutter-drawn bar;
        // Windows/Linux need the fully custom caption, hence the frameless path.
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: useNativeTitleBar,
      ),
    );
    if (!useNativeTitleBar) await windowManager.setAsFrameless();
    await windowManager.setResizable(true);
    if (PlatformInfo.isMacOS || PlatformInfo.isWindows) {
      await windowManager.setHasShadow(true);
    }
  }

  /// Called after Flutter has rendered the custom frame, avoiding native chrome
  /// flashing briefly before the first application frame on macOS.
  Future<void> show() async {
    if (!isSupported) return;
    await windowManager.show();
    await windowManager.focus();
  }
}
