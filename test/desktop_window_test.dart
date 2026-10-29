import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_jtt808_simulator/src/services/desktop_window_service.dart';
import 'package:flutter_jtt808_simulator/src/shared/widgets/desktop_window_frame.dart';
import 'package:flutter_jtt808_simulator/src/theme/shad_theme.dart';
import 'package:flutter_jtt808_simulator/src/theme/theme.dart';

import 'support/window_test_driver.dart';

late Map<String, dynamic> _english, _chinese;

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      locale.languageCode == 'zh' ? _chinese : _english;
}

void _windowTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    final previousPlatform = debugDefaultTargetPlatformOverride;
    try {
      await callback(tester);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        // Restore before the binding checks its global-variable invariants.
        semantics.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  Size size = const Size(1100, 800),
  bool dark = false,
  String locale = 'en',
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      assetLoader: const _Assets(),
      startLocale: Locale(locale),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      child: ScreenUtilInit(
        enableScaleWH: () => false,
        enableScaleText: () => false,
        builder: (context, _) => ShadApp.custom(
          theme: buildShadLightTheme(primaryColorHex: '#204bc3'),
          darkTheme: buildShadDarkTheme(primaryColorHex: '#204bc3'),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          appBuilder: (context) => MaterialApp(
            theme: buildLightTheme(primaryColorHex: '#204bc3'),
            darkTheme: buildDarkTheme(primaryColorHex: '#204bc3'),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            localizationsDelegates: [
              GlobalShadLocalizations.delegate,
              ...context.localizationDelegates,
            ],
            // Exercise the real builder position, above the navigator's overlay.
            builder: (context, child) =>
                ShadAppBuilder(child: DesktopWindowFrame(child: child!)),
            home: const Scaffold(body: Center(child: Text('Page content'))),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _captionLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WindowTestDriver driver;
  setUpAll(() async {
    _english = Map<String, dynamic>.from(
      jsonDecode(await rootBundle.loadString('assets/translations/en.json'))
          as Map,
    );
    _chinese = Map<String, dynamic>.from(
      jsonDecode(await rootBundle.loadString('assets/translations/zh.json'))
          as Map,
    );
  });
  setUp(() async {
    driver = WindowTestDriver()..install();
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableBuildModes = [];
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    driver.uninstall();
  });

  test('desktop startup sets the frame and size before it is shown', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await DesktopWindowService.instance.initialize();
    expect(driver.calls.first.method, 'ensureInitialized');
    final style =
        driver.calls.firstWhere((c) => c.method == 'setTitleBarStyle').arguments
            as Map;
    expect(style['titleBarStyle'], 'hidden');
    // macOS keeps the native traffic lights over the custom bar.
    expect(style['windowButtonVisibility'], isTrue);
    // Only Windows/Linux remove the frame; macOS must not call setAsFrameless.
    expect(driver.calls.any((c) => c.method == 'setAsFrameless'), isFalse);
    expect(
      driver.calls.any(
        (c) =>
            c.method == 'setResizable' &&
            (c.arguments as Map)['isResizable'] == true,
      ),
      isTrue,
    );
    final minimum =
        driver.calls.firstWhere((c) => c.method == 'setMinimumSize').arguments
            as Map;
    expect(minimum['width'], 1100);
    expect(minimum['height'], 720);
    final initial =
        driver.calls
                .firstWhere(
                  (call) =>
                      call.method == 'setBounds' &&
                      (call.arguments as Map).containsKey('width'),
                )
                .arguments
            as Map;
    expect(initial['width'], minimum['width']);
    expect(initial['height'], minimum['height']);
    expect(DesktopWindowService.initialSize, DesktopWindowService.minimumSize);
    expect(driver.calls.any((c) => c.method == 'show'), isFalse);
    await DesktopWindowService.instance.show();
    expect(driver.calls.last.method, 'focus');
    expect(driver.calls.any((c) => c.method == 'show'), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('windows startup removes the frame for a custom caption bar', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await DesktopWindowService.instance.initialize();
    final style =
        driver.calls.firstWhere((c) => c.method == 'setTitleBarStyle').arguments
            as Map;
    expect(style['titleBarStyle'], 'hidden');
    expect(style['windowButtonVisibility'], isFalse);
    expect(driver.calls.any((c) => c.method == 'setAsFrameless'), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('${platform.name} enforces a desktop-sized minimum window', () async {
      debugDefaultTargetPlatformOverride = platform;
      await DesktopWindowService.instance.initialize();
      final minimum =
          driver.calls
                  .firstWhere((call) => call.method == 'setMinimumSize')
                  .arguments
              as Map;
      expect(minimum['width'], 1100);
      expect(minimum['height'], 720);
      final initial =
          driver.calls
                  .firstWhere(
                    (call) =>
                        call.method == 'setBounds' &&
                        (call.arguments as Map).containsKey('width'),
                  )
                  .arguments
              as Map;
      expect(initial['width'], minimum['width']);
      expect(initial['height'], minimum['height']);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    _windowTest('${platform.name} never calls desktop plugins at any width', (
      tester,
    ) async {
      await _pump(tester, platform: platform, size: const Size(1440, 1000));
      await DesktopWindowService.instance.initialize();
      await DesktopWindowService.instance.show();
      expect(find.byType(DesktopWindowBar), findsNothing);
      expect(find.text('Page content'), findsOneWidget);
      expect(driver.calls, isEmpty);
    });
  }

  for (final dark in [false, true]) {
    _windowTest(
      '390px windows keeps caption controls in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pump(
          tester,
          platform: TargetPlatform.windows,
          size: const Size(390, 640),
          dark: dark,
          locale: 'zh',
        );
        expect(find.byType(DesktopWindowBar), findsOneWidget);
        expect(_captionLabel('最小化'), findsOneWidget);
        expect(_captionLabel('最大化'), findsOneWidget);
        expect(_captionLabel('关闭窗口'), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('desktop-window-bar')))
              .height,
          32,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _windowTest(
    'debug chrome switches on Windows without changing native platform',
    (tester) async {
      addTearDown(() => debugWindowStyle.value = null);
      await _pump(tester, platform: TargetPlatform.windows);
      expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
      debugWindowStyle.value = TargetPlatform.macOS;
      await tester.pumpAndSettle();
      expect(defaultTargetPlatform, TargetPlatform.windows);
      expect(find.byKey(const ValueKey('window-close')), findsNothing);
      expect(_captionLabel('Close window'), findsOneWidget);
      expect(find.text('Page content'), findsOneWidget);
      debugWindowStyle.value = TargetPlatform.windows;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _windowTest('macOS renders a borderless hidden-inset title area', (
    tester,
  ) async {
    await _pump(tester, platform: TargetPlatform.macOS);
    // The native traffic lights replace any custom caption bar visuals.
    expect(find.byType(DesktopWindowBar), findsNothing);
    expect(find.byKey(const ValueKey('window-minimize')), findsNothing);
    expect(find.byKey(const ValueKey('window-maximize')), findsNothing);
    expect(find.byKey(const ValueKey('window-close')), findsNothing);
    // No in-bar title: the app name lives in the sidebar / menu bar only.
    expect(find.byKey(const ValueKey('desktop-window-bar')), findsNothing);
    // The invisible top strip still carries drag + double-click zoom.
    final drag = find.byKey(const ValueKey('window-drag-area'));
    expect(drag, findsOneWidget);
    // Restored windows draw a 1px frame border, so the strip starts at (1,1).
    expect(
      tester.getTopLeft(drag),
      const Offset(1, 1),
      reason: 'the strip must cover the very top of the window',
    );
    expect(tester.getSize(drag).height, 32);
    await tester.drag(drag, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(driver.calls.any((c) => c.method == 'startDragging'), isTrue);
    await tester.tap(drag);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(drag);
    await tester.pumpAndSettle();
    expect(driver.maximized, isTrue);
    // Content receives a top inset so nothing hides under the traffic lights.
    expect(find.text('Page content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _windowTest(
    'caption buttons invoke native minimize, maximize, restore and close',
    (tester) async {
      await _pump(tester, platform: TargetPlatform.windows);
      await _tap(tester, 'window-minimize');
      expect(driver.calls.last.method, 'minimize');
      expect(driver.calls.any((c) => c.method == 'startDragging'), isFalse);
      await _tap(tester, 'window-maximize');
      expect(driver.maximized, isTrue);
      expect(_captionLabel('Restore window'), findsOneWidget);
      await _tap(tester, 'window-maximize');
      expect(driver.maximized, isFalse);
      expect(_captionLabel('Maximize'), findsOneWidget);
      await _tap(tester, 'window-close');
      expect(driver.calls.last.method, 'close');
      expect(tester.takeException(), isNull);
    },
  );

  _windowTest('drag and double-click use only the caption drag area', (
    tester,
  ) async {
    await _pump(tester, platform: TargetPlatform.windows);
    final drag = find.byKey(const ValueKey('window-drag-area'));
    await tester.drag(drag, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(driver.calls.any((c) => c.method == 'startDragging'), isTrue);
    await tester.tap(drag);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(drag);
    await tester.pumpAndSettle();
    expect(driver.maximized, isTrue);
  });

  _windowTest(
    'native focus, size and full-screen events synchronize controls',
    (tester) async {
      await _pump(tester, platform: TargetPlatform.windows);
      driver.maximized = true;
      for (final listener in windowManager.listeners) {
        listener.onWindowMaximize();
        listener.onWindowBlur();
      }
      await tester.pumpAndSettle();
      var bar = tester.widget<DesktopWindowBar>(find.byType(DesktopWindowBar));
      expect(bar.focused, isFalse);
      expect(bar.maximized, isTrue);
      driver.fullScreen = true;
      for (final listener in windowManager.listeners) {
        listener.onWindowEnterFullScreen();
      }
      await tester.pumpAndSettle();
      expect(_captionLabel('Exit full screen'), findsOneWidget);
      await _tap(tester, 'window-maximize');
      expect(driver.fullScreen, isFalse);
      for (final listener in windowManager.listeners) {
        listener.onWindowFocus();
      }
      await tester.pumpAndSettle();
      bar = tester.widget<DesktopWindowBar>(find.byType(DesktopWindowBar));
      expect(bar.focused, isTrue);
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    _windowTest(
      '${platform.name} enables resize hit regions only while restored',
      (tester) async {
        await _pump(tester, platform: platform);
        var edges = tester.widget<DragToResizeArea>(
          find.byType(DragToResizeArea),
        );
        expect(edges.enableResizeEdges, isNull);
        await tester.dragFrom(const Offset(2, 400), const Offset(20, 0));
        await tester.pumpAndSettle();
        expect(driver.calls.any((c) => c.method == 'startResizing'), isTrue);
        await _tap(tester, 'window-maximize');
        edges = tester.widget<DragToResizeArea>(find.byType(DragToResizeArea));
        expect(edges.enableResizeEdges, isEmpty);
      },
    );
  }

  _windowTest(
    'macOS retains AppKit resize handling and releases listeners on disposal',
    (tester) async {
      final before = windowManager.listeners.length;
      await _pump(tester);
      expect(find.byType(DragToResizeArea), findsNothing);
      expect(windowManager.listeners.length, before + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(windowManager.listeners.length, before);
    },
  );

  _windowTest(
    'tooltips work above the navigator and close hover uses semantic error color',
    (tester) async {
      await _pump(tester, platform: TargetPlatform.windows);
      final close = find.byKey(const ValueKey('window-close'));
      final button = tester.widget<ShadButton>(
        find.descendant(of: close, matching: find.byType(ShadButton)),
      );
      final colors = Theme.of(tester.element(close)).colorScheme;
      expect(button.hoverBackgroundColor, colors.error);
      expect(button.hoverForegroundColor, colors.onError);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 80));
      await mouse.moveTo(tester.getCenter(close));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Close window'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpAndSettle();
    },
  );

  test('window translations have identical keys', () {
    expect(
      (_english['window'] as Map).keys.toSet(),
      (_chinese['window'] as Map).keys.toSet(),
    );
  });
}
