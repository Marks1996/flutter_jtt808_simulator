import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_jtt808_simulator/src/app.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/screens/simulator_screen.dart';
import 'package:flutter_jtt808_simulator/src/services/desktop_window_service.dart';
import 'package:flutter_jtt808_simulator/src/utils/platform_info.dart';
import 'package:flutter_jtt808_simulator/src/shared/widgets/desktop_window_frame.dart';
import 'package:flutter_jtt808_simulator/src/routing/app_router.dart';
import 'package:flutter_jtt808_simulator/src/routing/app_routes.dart';
import 'support/window_test_driver.dart';

class _Repository implements SimulatorRepository {
  @override
  Future<SimulatorWorkspace> load() async => SimulatorWorkspace();
  @override
  Future<void> save(SimulatorWorkspace workspace) async {}
}

class _Assets extends AssetLoader {
  const _Assets(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

void main() {
  test('only the local simulator route is registered', () {
    final routes = appRouter.configuration.routes.whereType<GoRoute>().toList();
    expect(routes, hasLength(1));
    expect(routes.single.path, AppRoutes.home);
    expect(routes.single.name, 'home');
  });

  testWidgets(
    'the real application opens the local simulator without login or implicit connections',
    (tester) async {
      final driver = WindowTestDriver()..install();
      addTearDown(driver.uninstall);
      final desktop = DesktopWindowService.isSupported;
      tester.view.physicalSize = desktop
          ? DesktopWindowService.minimumSize
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      EasyLocalization.logger.enableBuildModes = [];
      await EasyLocalization.ensureInitialized();
      final data = await tester.runAsync(
        () => rootBundle.loadString('assets/translations/en.json'),
      );
      final controller = SimulatorController(_Repository());
      await controller.load();
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('zh')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          saveLocale: false,
          assetLoader: _Assets(
            Map<String, dynamic>.from(jsonDecode(data!) as Map),
          ),
          child: ProviderScope(
            overrides: [simulatorProvider.overrideWith((ref) => controller)],
            child: const App(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(App), findsOneWidget);
      expect(find.byType(SimulatorScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('window-drag-area')),
        desktop ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(DesktopWindowBar),
        desktop && !PlatformInfo.isMacOS ? findsOneWidget : findsNothing,
      );
      expect(find.byType(AppBar), desktop ? findsNothing : findsOneWidget);
      if (desktop) {
        expect(
          find.byKey(const ValueKey('sim-labeled-navigation')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sim-bottom-navigation')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('sim-navigation-rail')), findsNothing);
        // The platform selects desktop navigation even if Flutter is given a
        // size below the native window minimum, e.g. during a resize callback.
        tester.view.physicalSize = const Size(900, 720);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sim-labeled-navigation')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('sim-bottom-navigation')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('sim-navigation-rail')), findsNothing);
      } else {
        expect(
          find.byKey(const ValueKey('sim-bottom-navigation')),
          findsOneWidget,
        );
      }
      if (PlatformInfo.isMacOS) {
        final drag = find.byKey(const ValueKey('window-drag-area'));
        expect(
          tester.getTopLeft(find.text(tr('sim.console')).first).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(drag).dy),
          reason: 'macOS content must stay below the native drag strip.',
        );
      }
      if (!desktop) expect(driver.calls, isEmpty);
      expect(
        find.byKey(const ValueKey('console-create-terminal')),
        findsOneWidget,
      );
      expect(controller.onlineCount, 0);
      expect(controller.loadState.isSuccess, isTrue);
      await tester.tap(find.byKey(const ValueKey('console-create-terminal')));
      await tester.pumpAndSettle();
      final dialog = find.byType(ShadDialog);
      final frame = tester.getRect(
        find.descendant(of: dialog, matching: find.byType(DecoratedBox)).first,
      );
      final title = tester.getRect(
        find.descendant(
          of: dialog,
          matching: find.text(tr('sim.create_terminal')),
        ),
      );
      final close = find.byKey(const ValueKey('dialog-close'));
      expect(title.top - frame.top, 24);
      expect(title.left - frame.left, 24);
      expect(tester.getRect(close).top - frame.top, 8);
      expect(
        tester.widget<ShadDialog>(dialog).description,
        isA<Text>().having(
          (text) => text.data,
          'description',
          tr('sim.dialog.terminal_description'),
        ),
      );
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(ShadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}
