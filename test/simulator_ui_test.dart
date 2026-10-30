import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_jtt808_simulator/src/services/desktop_window_service.dart';
import 'package:flutter_jtt808_simulator/src/shared/app_assets.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/data/protocol/jt808_codec.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/log_detail_dialog.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/terminal_editor.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/route_editor.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/task_editor.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/workspace_transfer_dialog.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/screens/simulator_screen.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/route_planning_provider.dart';
import 'package:flutter_jtt808_simulator/src/utils/typedefs.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/route_planning_map.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/route_preview.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/sim_ui.dart';

import 'package:flutter_jtt808_simulator/src/shared/widgets/desktop_window_frame.dart';

import 'support/window_test_driver.dart';

late Map<String, dynamic> _english;
late Map<String, dynamic> _chinese;

const _osrmSettings = RoutePlanningSettings(
  provider: RoutingProvider.osrm,
  osrmUrl: RoutePlanningSettings.publicDemoUrl,
);

const _navigationArtwork = <String, String>{
  'console': 'assets/icons/navigation/board_24_color.svg',
  'terminals': 'assets/icons/navigation/phone_laptop_24_color.svg',
  'routes_tasks': 'assets/icons/navigation/location_ripple_24_color.svg',
  'protocol_logs': 'assets/icons/navigation/code_block_24_color.svg',
  'settings':
      'assets/icons/navigation/arrow_clockwise_dashes_settings_24_color.svg',
};

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      locale.languageCode == 'en' ? _english : _chinese;
}

class _MemoryRepository implements SimulatorRepository {
  _MemoryRepository([SimulatorWorkspace? workspace])
    : value = workspace ?? SimulatorWorkspace();
  SimulatorWorkspace value;
  bool failLoad = false;
  bool failSave = false;
  int writes = 0;
  Completer<void>? pendingSave;

  @override
  Future<SimulatorWorkspace> load() async {
    if (failLoad) throw StateError('test load failure');
    return value;
  }

  @override
  Future<void> save(SimulatorWorkspace workspace) async {
    writes++;
    if (failSave) throw StateError('test save failure');
    if (pendingSave != null) await pendingSave!.future;
    value = workspace;
  }
}

class _LogController extends SimulatorController {
  _LogController(super.repository, this.records);
  final List<ProtocolLog> records;
  @override
  List<ProtocolLog> get logs => List.unmodifiable(records);
  void addLog(ProtocolLog log) {
    records.add(log);
    notifyListeners();
  }
}

class _FakeRoutePlanner implements RoutePlanner {
  int calls = 0;
  bool fail = false;
  Completer<Either<Failure, PlannedRoute>>? pending;
  @override
  FutureEither<PlannedRoute> plan({
    required RoutePlanningSettings settings,
    required List<RouteWaypoint> waypoints,
    required RoutePlanningCancellation cancellation,
  }) async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) return left(const NetworkFailure('routing_network'));
    return right(
      PlannedRoute(
        origin: RoutePlanMetadata(
          provider: settings.provider,
          waypoints: waypoints,
        ),
        points: [
          waypoints.first,
          RouteWaypoint(
            (waypoints.first.latitude + waypoints.last.latitude) / 2 + .001,
            (waypoints.first.longitude + waypoints.last.longitude) / 2,
          ),
          waypoints.last,
        ],
      ),
    );
  }
}

class _TestApp extends ConsumerWidget {
  const _TestApp({this.windowFrame = false});
  final bool windowFrame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(simulatorProvider);
    final mode = switch (controller.workspace.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      enableScaleWH: () => false,
      enableScaleText: () => false,
      builder: (context, child) => ShadApp.custom(
        theme: buildShadLightTheme(primaryColorHex: '#204bc3'),
        darkTheme: buildShadDarkTheme(primaryColorHex: '#204bc3'),
        themeMode: mode,
        appBuilder: (context) => MaterialApp(
          theme: buildLightTheme(primaryColorHex: '#204bc3'),
          darkTheme: buildDarkTheme(primaryColorHex: '#204bc3'),
          themeMode: mode,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          localizationsDelegates: [
            GlobalShadLocalizations.delegate,
            ...context.localizationDelegates,
          ],
          builder: (context, child) => ShadAppBuilder(
            child: windowFrame ? DesktopWindowFrame(child: child!) : child!,
          ),
          home: const SimulatorScreen(),
        ),
      ),
    );
  }
}

Future<SimulatorController> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String theme = 'light',
  String language = 'zh',
  SimulatorWorkspace? workspace,
  _MemoryRepository? repository,
  List<ProtocolLog>? logs,
  RoutePlanner? planner,
  bool windowFrame = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo =
      repository ??
      _MemoryRepository(
        workspace?.copyWith(theme: theme) ?? SimulatorWorkspace(theme: theme),
      );
  final controller = logs == null
      ? SimulatorController(repo)
      : _LogController(repo, logs);
  await controller.load();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('zh'), Locale('en')],
      path: 'assets/translations',
      assetLoader: const _TestAssetLoader(),
      startLocale: Locale(language),
      fallbackLocale: const Locale('zh'),
      saveLocale: false,
      child: ProviderScope(
        overrides: [
          simulatorProvider.overrideWith((ref) => controller),
          if (planner != null) routePlannerProvider.overrideWithValue(planner),
        ],
        child: _TestApp(windowFrame: windowFrame),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _nav(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('nav-$key')));
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'Navigating to $key must not overflow.',
  );
}

Future<void> _chooseSelect(
  WidgetTester tester,
  String key,
  String option,
) async {
  final select = find.byKey(ValueKey(key));
  await tester.ensureVisible(select);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: select, matching: find.byType(ShadSelect<String>)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _revealSettings(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(of: find.byType(SimPage), matching: find.byType(Scrollable))
      .first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: scrollable,
      maxScrolls: 60,
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Finder _dialogCloseIcon() => find.byKey(const ValueKey('dialog-close'));

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

Finder _basemapInput(String key) => find.descendant(
  of: find.byKey(PageStorageKey(key)),
  matching: find.byType(EditableText),
);

void _expectOfficialDialog(
  WidgetTester tester, {
  required String title,
  required String description,
}) {
  final finder = find.byType(ShadDialog).last;
  final dialog = tester.widget<ShadDialog>(finder);
  expect((dialog.title! as Text).data, title);
  expect((dialog.description! as Text).data, description);
  expect(dialog.padding, isNull);
  expect(dialog.gap, isNull);
  expect(dialog.actionsGap, isNull);
  expect(dialog.titleStyle, isNull);
  expect(dialog.descriptionStyle, isNull);
  expect(dialog.titleTextAlign, isNull);
  expect(dialog.descriptionTextAlign, isNull);
  expect(dialog.titlePinned, isTrue);
  expect(dialog.descriptionPinned, isTrue);
  expect(dialog.actionsPinned, isNull);
  expect(dialog.actions.every((action) => action is ShadButton), isTrue);

  final titleFinder = find.descendant(of: finder, matching: find.text(title));
  final descriptionFinder = find.descendant(
    of: finder,
    matching: find.text(description),
  );
  final titleStyle = DefaultTextStyle.of(tester.element(titleFinder)).style;
  final descriptionStyle = DefaultTextStyle.of(
    tester.element(descriptionFinder),
  ).style;
  final libraryText = ShadTextTheme(family: 'IBM Plex Sans');
  final theme = ShadTheme.of(tester.element(finder));
  expect(titleStyle.fontSize, libraryText.large.fontSize);
  expect(titleStyle.fontWeight, libraryText.large.fontWeight);
  expect(descriptionStyle.fontSize, libraryText.muted.fontSize);
  expect(descriptionStyle.color, theme.colorScheme.mutedForeground);
  expect(
    tester.getTopLeft(descriptionFinder).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(titleFinder).dy),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Compile local SVGs outside fake async so image loading is deterministic.
    for (final asset in _navigationArtwork.values) {
      await SvgAssetLoader(asset).loadBytes(null);
    }
    // Read real translation assets outside widget tests' fake async zone.
    // The in-memory loader then makes localization deterministic on every pump.
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
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableBuildModes = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final theme in ['light', 'dark']) {
    testWidgets(
      '$theme desktop pages scroll behind a fixed titlebar fade',
      (tester) async {
        final driver = WindowTestDriver()..install();
        addTearDown(driver.uninstall);
        addTearDown(() => debugWindowStyle.value = null);
        await _pump(
          tester,
          size: const Size(1100, 720),
          theme: theme,
          windowFrame: true,
        );
        await _nav(tester, 'settings');
        final page = find.byType(SimPage);
        final list = find.descendant(of: page, matching: find.byType(ListView));
        final fade = find.byKey(const ValueKey('sim-titlebar-fade'));
        final sidebar = find.byKey(const ValueKey('sim-sidebar-panel'));
        final sidebarBefore = tester.getRect(sidebar);
        final header = find.byType(SimPageHeader);
        final headerBefore = tester.getRect(header);
        final viewportTop = tester.getTopLeft(list).dy;
        final drag = find.byKey(const ValueKey('window-drag-area'));
        expect(viewportTop, tester.getTopLeft(drag).dy);
        expect(sidebarBefore.top, tester.getRect(drag).bottom + SimSpace.ms);
        expect(headerBefore.top, viewportTop + 32 + SimStyle.pageInset);
        final fadeBefore = tester.getRect(fade);
        expect(fadeBefore.top, viewportTop);
        expect(fadeBefore.bottom, headerBefore.top);
        final gradient =
            (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                    .gradient!
                as LinearGradient;
        final colors = Theme.of(tester.element(page)).colorScheme;
        expect(gradient.colors.first, colors.surface);
        expect(gradient.colors.last, colors.surface.withValues(alpha: 0));
        expect(gradient.colors[1].a, closeTo(.9, .001));

        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        scrollable.position.jumpTo(40);
        await tester.pumpAndSettle();
        expect(tester.getRect(header).top, headerBefore.top - 40);
        expect(
          tester.getRect(header).top,
          lessThan(tester.getRect(drag).bottom),
        );
        expect(tester.getRect(fade), fadeBefore);
        expect(tester.getRect(sidebar), sidebarBefore);
        final ignored = find.ancestor(
          of: fade,
          matching: find.byType(IgnorePointer),
        );
        expect(tester.widget<IgnorePointer>(ignored.first).ignoring, isTrue);
        await tester.drag(drag, const Offset(40, 0));
        await tester.pumpAndSettle();
        expect(
          driver.calls.any((call) => call.method == 'startDragging'),
          isTrue,
        );

        // Dialogs keep the full window; the page fade stays behind the modal.
        await _nav(tester, 'terminals');
        await tester.tap(find.byKey(const ValueKey('create-terminal')));
        await tester.pumpAndSettle();
        final dialog = find.byType(ShadDialog);
        expect(dialog, findsOneWidget);
        expect(find.descendant(of: dialog, matching: fade), findsNothing);
        expect(
          tester.getCenter(dialog).dy,
          closeTo(tester.view.physicalSize.height / 2, 1),
        );
        await tester.tap(_dialogCloseIcon());
        await tester.pumpAndSettle();

        final fadeBeforePreview = tester.getRect(fade);
        final sidebarBeforePreview = tester.getRect(sidebar);
        debugWindowStyle.value = TargetPlatform.windows;
        await tester.pumpAndSettle();
        expect(fade, findsOneWidget);
        expect(tester.getRect(fade), fadeBeforePreview);
        expect(tester.getRect(sidebar), sidebarBeforePreview);
        expect(find.byType(DesktopWindowBar), findsOneWidget);
        debugWindowStyle.value = TargetPlatform.macOS;
        await tester.pumpAndSettle();
        expect(fade, findsOneWidget);
        expect(tester.getRect(fade), fadeBeforePreview);
        expect(tester.getRect(sidebar), sidebarBeforePreview);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'mobile platforms keep scrolling below their safe area without a titlebar fade',
    (tester) async {
      final driver = WindowTestDriver()..install();
      addTearDown(driver.uninstall);
      await _pump(tester, size: const Size(1100, 720), windowFrame: true);
      await _nav(tester, 'settings');
      expect(find.byKey(const ValueKey('sim-titlebar-fade')), findsNothing);
      final list = find.descendant(
        of: find.byType(SimPage),
        matching: find.byType(ListView),
      );
      expect(tester.widget<ListView>(list).padding, const EdgeInsets.all(16));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final size in [const Size(1100, 720), const Size(390, 844)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets(
        'all dialogs follow the official example at ${size.width} in $theme',
        (tester) async {
          const terminal = TerminalConfig(id: 'dialog-terminal');
          final route = RouteCsv.parse(
            RouteCsv.example,
            id: 'dialog-route',
            name: 'Route',
          );
          const task = DriveTask(
            id: 'dialog-task',
            name: 'Playback',
            terminalId: 'dialog-terminal',
            routeId: 'dialog-route',
          );
          final controller = await _pump(
            tester,
            size: size,
            theme: theme,
            language: 'en',
            workspace: SimulatorWorkspace(
              terminals: [terminal],
              routes: [route],
              tasks: [task],
            ),
          );
          final context = tester.element(find.byType(SimulatorScreen));
          final dialogs = <(String, String, Future<void> Function())>[
            (
              'sim.create_terminal',
              'sim.dialog.terminal_description',
              () => showTerminalEditor(context, controller),
            ),
            (
              'sim.edit_terminal',
              'sim.dialog.terminal_description',
              () => showTerminalEditor(context, controller, terminal),
            ),
            (
              'sim.create_route',
              'sim.dialog.route_description',
              () => showRouteEditor(context, controller),
            ),
            (
              'sim.edit_route',
              'sim.dialog.route_description',
              () => showRouteEditor(context, controller, route),
            ),
            (
              'sim.create_task',
              'sim.dialog.task_description',
              () => showTaskEditor(context, controller),
            ),
            (
              'sim.edit_task',
              'sim.dialog.task_description',
              () => showTaskEditor(context, controller, task),
            ),
            (
              'sim.import_workspace',
              'sim.dialog.import_description',
              () => showWorkspaceTransfer(context, controller, importing: true),
            ),
            (
              'sim.export_workspace',
              'sim.dialog.export_description',
              () =>
                  showWorkspaceTransfer(context, controller, importing: false),
            ),
            (
              'sim.log_detail',
              'sim.dialog.log_description',
              () => showLogDetail(
                context,
                controller,
                ProtocolLog(
                  terminalId: terminal.id,
                  direction: LogDirection.event,
                  message: 'Recorded event',
                ),
              ),
            ),
          ];
          for (final (titleKey, descriptionKey, open) in dialogs) {
            unawaited(open());
            await tester.pumpAndSettle();
            _expectOfficialDialog(
              tester,
              title: tr(titleKey),
              description: tr(descriptionKey),
            );
            final close = find
                .descendant(
                  of: find.byType(ShadDialog),
                  matching: find.byType(ShadIconButton),
                )
                .last;
            final button = tester.widget<ShadIconButton>(close);
            final colors = ShadTheme.of(tester.element(close)).colorScheme;
            expect(button.width, 20);
            expect(button.height, 20);
            expect(
              button.foregroundColor,
              colors.foreground.withValues(alpha: .5),
            );
            expect(button.hoverBackgroundColor, Colors.transparent);
            expect(button.hoverForegroundColor, colors.foreground);
            expect(button.pressedForegroundColor, colors.foreground);
            await tester.tap(close);
            await tester.pumpAndSettle();
            expect(find.byType(ShadDialog), findsNothing);
          }
          for (final destructive in [false, true]) {
            final result = simConfirm(
              context,
              title: tr('sim.discard_changes_title'),
              body: tr('sim.discard_changes_body'),
              cancel: tr('sim.keep_editing'),
              confirm: tr('sim.discard_changes'),
              destructive: destructive,
            );
            await tester.pumpAndSettle();
            _expectOfficialDialog(
              tester,
              title: tr('sim.discard_changes_title'),
              description: tr('sim.discard_changes_body'),
            );
            final dialog = tester.widget<ShadDialog>(find.byType(ShadDialog));
            expect(dialog.variant, ShadDialogVariant.alert);
            expect(
              (dialog.actions.first as ShadButton).variant,
              ShadButtonVariant.outline,
            );
            expect(
              (dialog.actions.last as ShadButton).variant,
              destructive
                  ? ShadButtonVariant.destructive
                  : ShadButtonVariant.primary,
            );
            await tester.tap(find.text(tr('sim.keep_editing')));
            await tester.pumpAndSettle();
            expect(await result, isFalse);
          }
        },
      );
    }
  }

  testWidgets(
    'empty workspace stays offline and all five views navigate on phone',
    (tester) async {
      final controller = await _pump(tester);
      expect(find.text('尚未添加终端'), findsOneWidget);
      expect(find.textContaining('0 / 0'), findsOneWidget);
      expect(controller.onlineCount, 0);
      expect(controller.terminals, isEmpty);
      expect(find.byType(RoutePreview), findsNothing);
      for (final key in [
        'terminals',
        'routes_tasks',
        'protocol_logs',
        'settings',
        'console',
      ]) {
        await _nav(tester, key);
      }
      expect(
        find.byKey(const ValueKey('console-create-terminal')),
        findsOneWidget,
      );
    },
  );

  test(
    'navigation bundles original multicolor SVGs and the upstream MIT license',
    () async {
      for (final asset in _navigationArtwork.values) {
        final source = await rootBundle.loadString(asset);
        expect(source, contains('viewBox="0 0 24 24"'));
        expect(source, contains('<linearGradient'));
        final colors = RegExp(r'#[0-9a-fA-F]{6}')
            .allMatches(source)
            .map((match) => match.group(0)!.toUpperCase())
            .toSet();
        expect(colors.length, greaterThanOrEqualTo(3), reason: asset);
        expect(source, isNot(contains('currentColor')));
      }
      final license = await rootBundle.loadString(
        'assets/icons/navigation/LICENSE',
      );
      expect(license, contains('MIT License'));
      expect(license, contains('Copyright (c) 2020 Microsoft Corporation'));
    },
  );

  for (final theme in ['light', 'dark']) {
    testWidgets(
      'sidebar labels align left and use original color artwork in $theme',
      (tester) async {
        await _pump(
          tester,
          size: const Size(1100, 720),
          theme: theme,
          language: 'en',
        );
        final context = tester.element(
          find.byKey(const ValueKey('nav-console')),
        );
        double? labelLeft;
        for (final selected in _navigationArtwork.keys) {
          await _nav(tester, selected);
          for (final entry in _navigationArtwork.entries) {
            final nav = find.byKey(ValueKey('nav-${entry.key}'));
            final button = tester.widget<ShadButton>(nav);
            final label = find.descendant(
              of: nav,
              matching: find.text(tr('sim.${entry.key}')),
            );
            expect(tester.widget<Text>(label).textAlign, TextAlign.left);
            final left = tester.getTopLeft(label).dx;
            labelLeft ??= left;
            expect(left, closeTo(labelLeft, .01));
            expect(button.mainAxisAlignment, MainAxisAlignment.start);
            final icon = button.leading! as SvgPicture;
            final loader = icon.bytesLoader as SvgAssetLoader;
            expect(loader.assetName, entry.value);
            expect(loader.colorMapper, isNull);
            expect(icon.colorFilter, isNull);
            expect(icon.width, 20);
            expect(icon.height, 20);
            expect(icon.excludeFromSemantics, isTrue);
            expect(
              button.backgroundColor,
              selected == entry.key
                  ? context.colors.surfaceContainerHigh
                  : null,
            );
            expect(tester.getSize(nav).height, 40);
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1100, 720),
  ]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('app logo has rounded corners at ${size.width} in $theme', (
        tester,
      ) async {
        await _pump(tester, size: size, theme: theme);
        final logo = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName == AppAssets.logo,
        );
        expect(logo, findsOneWidget);
        final clip = tester.widget<ClipRRect>(
          find.ancestor(of: logo, matching: find.byType(ClipRRect)).first,
        );
        expect(clip.borderRadius, AppBorders.sm);
        expect(clip.clipBehavior, Clip.antiAlias);
        final image = tester.widget<Image>(logo);
        final expectedSize = size.width < 640 ? 28.0 : 32.0;
        expect(image.width, expectedSize);
        expect(image.height, expectedSize);
        expect(image.excludeFromSemantics, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    for (final language in ['zh', 'en']) {
      testWidgets(
        'settings keep essential guidance without redundant descriptions at ${size.width} in $language',
        (tester) async {
          await _pump(
            tester,
            size: size,
            language: language,
            theme: language == 'zh' ? 'light' : 'dark',
          );
          await _nav(tester, 'settings');
          for (final key in [
            'basemap_settings_help',
            'routing.settings_help',
            'workspace_help',
            'workspace_contents',
            'reference_disclaimer',
            'tianditu_layers_help',
            'keyless.osrm_help',
          ]) {
            expect(find.text(tr('sim.$key')), findsNothing, reason: key);
          }
          for (final key in [
            'theme',
            'language',
            'basemap_settings',
            'routing.settings',
            'tianditu_key_help',
            'keyless.imagery_help',
            'basemap_network_hint',
            'routing.amap_key_help',
            'routing.amap_authorized',
            'routing.privacy',
            'workspace_secret_warning',
            'support_scope_body',
            'unsupported_scope',
            'coordinate_policy_body',
          ]) {
            final text = find.text(tr('sim.$key'));
            await _revealSettings(tester, text);
            expect(text, findsOneWidget, reason: key);
            for (final removed in [
              'basemap_settings_help',
              'routing.settings_help',
              'workspace_help',
              'workspace_contents',
              'reference_disclaimer',
              'tianditu_layers_help',
              'keyless.osrm_help',
            ]) {
              expect(find.text(tr('sim.$removed')), findsNothing);
            }
          }
          for (final action in [
            find.byKey(const ValueKey('save-basemap')),
            find.byKey(const ValueKey('save-routing')),
            find.text(tr('sim.export_workspace')),
            find.text(tr('sim.import_workspace')),
          ]) {
            await _revealSettings(tester, action);
            expect(action, findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('canvas and switch colors stay consistent in $theme', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1100, 720), theme: theme);
      final canvas = find.byKey(const ValueKey('sim-workspace-surface'));
      final context = tester.element(canvas);
      final colors = Theme.of(context).colorScheme;
      final shad = ShadTheme.of(context);
      expect(tester.widget<ColoredBox>(canvas).color, colors.surface);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        colors.surface,
      );
      expect(shad.colorScheme.background, colors.surface);
      expect(shad.colorScheme.card, colors.surfaceContainerLow);
      if (theme == 'light') {
        expect(
          colors.surface.computeLuminance(),
          lessThan(colors.surfaceContainerLow.computeLuminance()),
        );
      }

      await _nav(tester, 'settings');
      final toggle = find.byKey(const ValueKey('basemap-default-enabled'));
      await _revealSettings(tester, toggle);
      final switchTheme = ShadTheme.of(tester.element(toggle)).switchTheme;
      expect(switchTheme.thumbColor, colors.onPrimary);
      expect(switchTheme.thumbColor!.computeLuminance(), greaterThan(.9));
      expect(switchTheme.checkedTrackColor, colors.primary);
      expect(switchTheme.uncheckedTrackColor, colors.outline);
      for (final checked in [true, false]) {
        expect(tester.widget<ShadSwitch>(toggle).value, checked);
        final decorations = tester
            .widgetList<ShadDecorator>(
              find.descendant(of: toggle, matching: find.byType(ShadDecorator)),
            )
            .map((widget) => widget.decoration)
            .whereType<ShadDecoration>()
            .toList();
        expect(
          decorations.any(
            (decoration) =>
                decoration.shape == BoxShape.circle &&
                decoration.color == colors.onPrimary,
          ),
          isTrue,
        );
        expect(
          decorations.any(
            (decoration) =>
                decoration.color == (checked ? colors.primary : colors.outline),
          ),
          isTrue,
        );
        if (checked) {
          await tester.tapAt(tester.getTopLeft(toggle) + const Offset(20, 12));
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('reference shell and settings card structure in $theme', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1100, 720), theme: theme);
      final sidebar = find.byKey(const ValueKey('sim-labeled-navigation'));
      expect(tester.getSize(sidebar).width, 248);
      final panel = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('sim-sidebar-panel')),
      );
      final colors = Theme.of(tester.element(sidebar)).colorScheme;
      final decoration = panel.decoration as BoxDecoration;
      expect(decoration.color, colors.surfaceContainerLow);
      expect(decoration.borderRadius, AppBorders.card);
      expect(
        find.byKey(const ValueKey('sim-workspace-surface')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('nav-settings'))).dy,
        lessThan(400),
      );
      final statistics = find.byKey(const ValueKey('console-statistics'));
      expect(
        find.descendant(of: statistics, matching: find.text('0 / 0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: statistics, matching: find.text('0')),
        findsNWidgets(3),
      );
      await _nav(tester, 'settings');
      final appearance = find.ancestor(
        of: find.text(tr('sim.appearance_language')),
        matching: find.byType(SimPanel),
      );
      final card = tester.widget<ShadCard>(
        find.descendant(of: appearance, matching: find.byType(ShadCard)),
      );
      expect(card.backgroundColor, colors.surfaceContainerLow);
      expect(card.radius, AppBorders.card);
      final save = find.byKey(const ValueKey('save-basemap'));
      await _revealSettings(tester, save);
      final title = find.text(tr('sim.basemap_settings'));
      expect(
        (tester.getCenter(title).dy - tester.getCenter(save).dy).abs(),
        lessThan(1),
      );
      final shadTheme = ShadTheme.of(tester.element(save));
      final shad = shadTheme.colorScheme;
      expect(shad.primary, colors.primary);
      expect(shad.primaryForeground, colors.onPrimary);
      expect(shadTheme.outlineButtonTheme.foregroundColor, colors.onSurface);
      expect(shadTheme.ghostButtonTheme.foregroundColor, colors.onSurface);
      final linkColor = shadTheme.linkButtonTheme.foregroundColor!;
      expect(shadTheme.linkButtonTheme.hoverForegroundColor, linkColor);
      final linkLuminances = [
        linkColor.computeLuminance(),
        colors.surfaceContainerLow.computeLuminance(),
      ]..sort();
      expect(
        (linkLuminances.last + .05) / (linkLuminances.first + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        (colors.onPrimary.computeLuminance() + .05) /
            (colors.primary.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      final routingSave = find.byKey(const ValueKey('save-routing'));
      await _revealSettings(tester, routingSave);
      expect(
        (tester.getCenter(find.text(tr('sim.routing.settings'))).dy -
                tester.getCenter(routingSave).dy)
            .abs(),
        lessThan(1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact sidebar and field grids use the available space', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1440, 1000));
    final nav = find.byKey(const ValueKey('nav-console'));
    expect(tester.getSize(nav).height, lessThanOrEqualTo(40));
    final shadColors = ShadTheme.of(tester.element(nav)).colorScheme;
    final surface = Theme.of(tester.element(nav)).colorScheme;
    expect(shadColors.secondary, surface.surfaceContainerHigh);
    expect(shadColors.secondaryForeground, surface.onSurface);
    expect(shadColors.accent, surface.surfaceContainerHighest);
    expect(SimSpace.lg, 16);
    expect(SimSpace.md, 12);
    await _nav(tester, 'settings');
    final selects = find.byType(ShadSelectFormField<String>);
    expect(selects, findsNWidgets(2));
    expect(tester.getSize(selects.first).width, lessThanOrEqualTo(220));
    expect(tester.getSize(selects.last).width, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('simulator controls use shadcn inputs, selects and dialogs', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1440, 1000));
    expect(find.byType(ShadCard), findsWidgets);
    expect(find.byType(ShadButton), findsWidgets);
    await _nav(tester, 'settings');
    expect(find.byType(ShadSelectFormField<String>), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.byType(ShadSelect<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Appearance & language'), findsOneWidget);
    await _nav(tester, 'terminals');
    await tester.tap(find.byKey(const ValueKey('create-terminal')));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byType(ShadInputFormField), findsWidgets);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shadcn task menu preserves edit and delete confirmation', (
    tester,
  ) async {
    final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
    final controller = await _pump(
      tester,
      size: const Size(1440, 1000),
      language: 'en',
      workspace: SimulatorWorkspace(
        terminals: const [TerminalConfig(id: 't')],
        routes: [route],
        tasks: const [
          DriveTask(
            id: 'task',
            name: 'Playback',
            terminalId: 't',
            routeId: 'r',
          ),
        ],
      ),
    );
    await _nav(tester, 'routes_tasks');
    final menu = find.byType(ShadMenubarItem);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete task'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(controller.tasks, hasLength(1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.tasks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets(
        'visual route creation plans and saves WGS84 at ${size.width} in $theme',
        (tester) async {
          final planner = _FakeRoutePlanner();
          final controller = await _pump(
            tester,
            size: size,
            theme: theme,
            language: 'en',
            planner: planner,
            workspace: SimulatorWorkspace(
              routing: _osrmSettings,
              basemap: const BasemapSettings(enabled: false),
            ),
          );
          await _nav(tester, 'routes_tasks');
          await tester.tap(find.text(tr('sim.create_route')).first);
          await tester.pumpAndSettle();
          expect(find.byType(RoutePlanningMap), findsOneWidget);
          await tester.enterText(_input('route-name'), 'Visual driving route');
          final mapFinder = find.descendant(
            of: find.byType(RoutePlanningMap),
            matching: find.byType(FlutterMap),
          );
          final center = tester.getRect(mapFinder).center;
          await tester.tapAt(center + const Offset(-40, 0));
          await tester.pumpAndSettle();
          await tester.tapAt(center + const Offset(40, -15));
          await tester.pumpAndSettle();
          final selected = tester
              .widget<RoutePlanningMap>(find.byType(RoutePlanningMap))
              .waypoints;
          expect(selected.length, 2);
          expect(
            planner.calls,
            0,
            reason: 'Selecting points must not request directions.',
          );
          expect(
            tester
                .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
                .enabled,
            isFalse,
          );
          final plan = find.byKey(const ValueKey('plan-route'));
          await tester.ensureVisible(plan);
          await tester.pumpAndSettle();
          await tester.tap(plan);
          await tester.pumpAndSettle();
          expect(planner.calls, 1);
          expect(
            find.textContaining(
              tr('sim.routing.ready', namedArgs: {'points': '3'}),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
                .enabled,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('save-route')));
          await tester.pumpAndSettle();
          expect(controller.routes.single.coordinateSystem, 'WGS84');
          expect(controller.routes.single.points.length, 3);
          expect(controller.routes.single.planning!.waypoints, selected);
          expect(
            controller.routes.single.planning!.provider,
            RoutingProvider.osrm,
          );
          expect(
            controller.routes.single.points.every((p) => p.speed == 40),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'visual route edits invalidate geometry and recover after planning errors',
    (tester) async {
      final planner = _FakeRoutePlanner()..fail = true;
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        planner: planner,
        workspace: SimulatorWorkspace(
          routing: _osrmSettings,
          basemap: const BasemapSettings(enabled: false),
        ),
      );
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text(tr('sim.create_route')).first);
      await tester.pumpAndSettle();
      await tester.enterText(_input('route-name'), 'Planned test');
      final add = find.byKey(const ValueKey('route-add-waypoint'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.enterText(
        _input('route-waypoint-coordinate'),
        '39.9042,116.4074',
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(
        _input('route-waypoint-coordinate'),
        '39.91,116.42',
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      final plan = find.byKey(const ValueKey('plan-route'));
      await tester.ensureVisible(plan);
      await tester.pumpAndSettle();
      await tester.tap(plan);
      await tester.pumpAndSettle();
      expect(find.text(tr('sim.errors.routing_network')), findsOneWidget);
      expect(controller.routes, isEmpty);
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
            .enabled,
        isFalse,
      );
      planner.fail = false;
      await tester.ensureVisible(plan);
      await tester.pumpAndSettle();
      await tester.tap(plan);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
            .enabled,
        isTrue,
      );
      final first = find.byKey(const ValueKey('route-waypoint-0'));
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.enterText(
        _input('route-waypoint-coordinate'),
        '39.905,116.408',
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
            .enabled,
        isFalse,
      );
      expect(
        planner.calls,
        2,
        reason: 'Moving a stop requires an explicit new plan.',
      );
      await tester.tap(_dialogCloseIcon());
      await tester.pumpAndSettle();
      expect(find.text(tr('sim.discard_changes_title')), findsOneWidget);
      await tester.tap(find.text(tr('sim.discard_changes')));
      await tester.pumpAndSettle();
      expect(controller.routes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'routing settings validate and preserve independent OSRM and Amap credentials',
    (tester) async {
      final planner = _FakeRoutePlanner();
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        planner: planner,
        workspace: SimulatorWorkspace(routing: _osrmSettings),
      );
      await _nav(tester, 'settings');
      final pageScroll = find
          .descendant(
            of: find.byType(SimPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final url = _basemapInput('routing-osrm-url');
      await tester.scrollUntilVisible(url, 250, scrollable: pageScroll);
      await tester.pumpAndSettle();
      await tester.enterText(url, 'http://remote.example.com');
      final save = find.byKey(const ValueKey('save-routing'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(tr('sim.errors.routing_url')), findsOneWidget);
      expect(controller.workspace.routing, _osrmSettings);
      await tester.ensureVisible(url);
      await tester.pumpAndSettle();
      await tester.enterText(url, 'https://routing.example.com');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      final select = find.byType(ShadSelectFormField<RoutingProvider>);
      await tester.ensureVisible(select);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: select,
          matching: find.byType(ShadSelect<RoutingProvider>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('sim.routing.provider.amap')).last);
      await tester.pumpAndSettle();
      final key = _basemapInput('routing-amap-key');
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      await tester.enterText(key, 'test-web-service-key');
      expect(tester.widget<EditableText>(key).obscureText, isTrue);
      final authorization = find.byKey(
        const ValueKey('routing-amap-authorized'),
      );
      await tester.ensureVisible(authorization);
      await tester.pumpAndSettle();
      await tester.tap(authorization);
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(controller.workspace.routing.provider, RoutingProvider.amap);
      expect(
        controller.workspace.routing.osrmUrl,
        'https://routing.example.com',
      );
      expect(controller.workspace.routing.amapKey, 'test-web-service-key');
      expect(controller.workspace.basemap, const BasemapSettings());
      expect(planner.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '18-point routes still allow selecting a map marker and replacing its location',
    (tester) async {
      final planner = _FakeRoutePlanner();
      final points = [
        for (var i = 0; i < 18; i++)
          RouteWaypoint(39.9 + i * .005, 116.4 + i * .005),
      ];
      final route = DriveRoute(
        id: 'full',
        name: 'Full route',
        planning: RoutePlanMetadata(
          provider: RoutingProvider.osrm,
          waypoints: points,
        ),
        points: [
          for (final p in points)
            LocationFix(
              latitude: p.latitude,
              longitude: p.longitude,
              speed: 40,
            ),
        ],
      );
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        planner: planner,
        workspace: SimulatorWorkspace(
          routes: [route],
          basemap: const BasemapSettings(enabled: false),
        ),
      );
      showRouteEditor(
        tester.element(find.byType(SimulatorScreen)),
        controller,
        route,
      );
      await tester.pumpAndSettle();
      var map = tester.widget<RoutePlanningMap>(find.byType(RoutePlanningMap));
      expect(map.canPick, isFalse);
      final marker = find.byKey(const ValueKey('waypoint-marker-17'));
      expect(tester.widget<ShadButton>(marker).enabled, isTrue);
      await tester.tap(marker);
      await tester.pumpAndSettle();
      map = tester.widget<RoutePlanningMap>(find.byType(RoutePlanningMap));
      expect(map.selected, 17);
      expect(map.canPick, isTrue);
      final mapFinder = find.descendant(
        of: find.byType(RoutePlanningMap),
        matching: find.byType(FlutterMap),
      );
      await tester.tapAt(
        tester.getRect(mapFinder).center + const Offset(90, 35),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      map = tester.widget<RoutePlanningMap>(find.byType(RoutePlanningMap));
      expect(map.waypoints.length, 18);
      expect(map.waypoints.first, points.first);
      expect(map.waypoints.last, isNot(points.last));
      expect(planner.calls, 0);
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
            .enabled,
        isFalse,
      );
      expect(
        controller.routes.single.points.last.latitude,
        points.last.latitude,
        reason:
            'The saved route must remain unchanged until a new plan is saved.',
      );
      final viewport = find
          .ancestor(
            of: find.byKey(const ValueKey('route-planning-controls')),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final scrollable = find
          .descendant(of: viewport, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final saveRect = tester.getRect(find.byKey(const ValueKey('save-route')));
      final titleRect = tester.getRect(find.text(tr('sim.edit_route')));
      final viewportRect = tester.getRect(viewport);
      await tester.dragFrom(
        Offset(viewportRect.right - 4, viewportRect.center.dy),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(
        tester.getRect(find.byKey(const ValueKey('save-route'))),
        saveRect,
      );
      expect(tester.getRect(find.text(tr('sim.edit_route'))), titleRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved planned route reopens with stops and changes speed without requesting directions',
    (tester) async {
      final planner = _FakeRoutePlanner();
      final origin = RoutePlanMetadata(
        provider: RoutingProvider.osrm,
        waypoints: const [
          RouteWaypoint(39.9042, 116.4074),
          RouteWaypoint(39.91, 116.42),
        ],
      );
      final route = DriveRoute(
        id: 'planned',
        name: 'Saved driving route',
        planning: origin,
        points: const [
          LocationFix(latitude: 39.9042, longitude: 116.4074, speed: 40),
          LocationFix(latitude: 39.91, longitude: 116.42, speed: 40),
        ],
      );
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        planner: planner,
        workspace: SimulatorWorkspace(
          routes: [route],
          basemap: const BasemapSettings(enabled: false),
        ),
      );
      showRouteEditor(
        tester.element(find.byType(SimulatorScreen)),
        controller,
        controller.routes.single,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RoutePlanningMap>(find.byType(RoutePlanningMap))
            .waypoints,
        origin.waypoints,
      );
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('save-route')))
            .enabled,
        isTrue,
      );
      final speed = _input('route-planned-speed');
      await tester.ensureVisible(speed);
      await tester.pumpAndSettle();
      await tester.enterText(speed, '65');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-route')));
      await tester.pumpAndSettle();
      expect(controller.routes.length, 1);
      expect(controller.routes.single.planning!.waypoints, origin.waypoints);
      expect(
        controller.routes.single.points.every((p) => p.speed == 65),
        isTrue,
      );
      expect(planner.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route editor uses a contained focus border and no empty preview',
    (tester) async {
      await _pump(tester, size: const Size(1100, 720));
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text('新增线路').first);
      await tester.pumpAndSettle();
      expect(find.byType(RoutePreview), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('route-name'))).width,
        lessThanOrEqualTo(1040),
      );
      await tester.tap(find.text(tr('sim.routing.csv_tab')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_input('route-csv'));
      await tester.pumpAndSettle();
      await tester.tap(_input('route-csv'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('route-name'));
      final before = tester.getSize(field);
      await tester.ensureVisible(_input('route-name'));
      await tester.pumpAndSettle();
      await tester.tap(_input('route-name'));
      await tester.pumpAndSettle();
      final input = tester.widget<ShadInput>(
        find.descendant(of: field, matching: find.byType(ShadInput)),
      );
      expect(input.decoration?.disableSecondaryBorder, isTrue);
      expect(
        input.decoration?.focusedBorder?.radius,
        input.decoration?.border?.radius,
      );
      expect(tester.getSize(field), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1100, 720), const Size(390, 844)]) {
    for (final theme in ['light', 'dark']) {
      for (final language in ['zh', 'en']) {
        testWidgets(
          'route editor split and scrollbar gutter at ${size.width} in $theme / $language',
          (tester) async {
            final controller = await _pump(
              tester,
              size: size,
              theme: theme,
              language: language,
              workspace: SimulatorWorkspace(
                basemap: const BasemapSettings(enabled: false),
              ),
            );
            showRouteEditor(
              tester.element(find.byType(SimulatorScreen)),
              controller,
            );
            await tester.pumpAndSettle();
            final dialog = tester.widget<ShadDialog>(find.byType(ShadDialog));
            expect(dialog.constraints!.maxWidth, 1040);
            expect(
              dialog.scrollPadding,
              EdgeInsetsDirectional.only(end: SimSpace.lg),
            );
            final controls = find.byKey(
              const ValueKey('route-planning-controls'),
            );
            final map = find.byKey(const ValueKey('route-planning-map-pane'));
            final controlsRect = tester.getRect(controls);
            final mapRect = tester.getRect(map);
            final viewport = find
                .ancestor(of: map, matching: find.byType(SingleChildScrollView))
                .first;
            expect(
              tester.getRect(viewport).right - mapRect.right,
              greaterThanOrEqualTo(SimSpace.lg - 1),
            );
            if (size.width >= 1000) {
              expect(
                find.byKey(const ValueKey('route-planning-split')),
                findsOneWidget,
              );
              expect(controlsRect.right, lessThan(mapRect.left));
              expect(controlsRect.top, closeTo(mapRect.top, 1));
              expect(
                tester.getSize(find.byKey(const ValueKey('route-name'))).width,
                greaterThan(900),
              );
            } else {
              expect(
                find.byKey(const ValueKey('route-planning-stacked')),
                findsOneWidget,
              );
              expect(mapRect.bottom, lessThan(controlsRect.top));
            }
            _expectOfficialDialog(
              tester,
              title: tr('sim.create_route'),
              description: tr('sim.dialog.route_description'),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final size in [const Size(1100, 720), const Size(390, 844)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('CSV route preview layout at ${size.width} in $theme', (
        tester,
      ) async {
        final route = RouteCsv.parse(
          RouteCsv.example,
          id: 'csv-layout',
          name: 'CSV route',
        );
        final controller = await _pump(
          tester,
          size: size,
          theme: theme,
          workspace: SimulatorWorkspace(
            routes: [route],
            basemap: const BasemapSettings(enabled: false),
          ),
        );
        showRouteEditor(
          tester.element(find.byType(SimulatorScreen)),
          controller,
          route,
        );
        await tester.pumpAndSettle();
        final editorRect = tester.getRect(
          find.byKey(const ValueKey('route-csv')),
        );
        final preview = find.byType(RoutePreview);
        final previewRect = tester.getRect(preview);
        if (size.width >= 1000) {
          expect(find.byKey(const ValueKey('route-csv-split')), findsOneWidget);
          expect(editorRect.right, lessThan(previewRect.left));
          final viewport = find
              .ancestor(
                of: preview,
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          expect(
            tester.getRect(viewport).right - previewRect.right,
            greaterThanOrEqualTo(SimSpace.lg - 1),
          );
        } else {
          expect(find.byKey(const ValueKey('route-csv-split')), findsNothing);
          expect(editorRect.bottom, lessThan(previewRect.top));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'terminal editor validates phone, port, identity and saves user input only',
    (tester) async {
      final controller = await _pump(tester, size: const Size(1440, 1000));
      await _nav(tester, 'terminals');
      await tester.tap(find.byKey(const ValueKey('create-terminal')));
      await tester.pumpAndSettle();
      await tester.enterText(_input('terminal-phone'), '123');
      await tester.enterText(_input('terminal-port'), '0');
      await tester.enterText(_input('terminal-manufacturer'), 'TOOLONG');
      await tester.tap(find.byKey(const ValueKey('save-terminal')));
      await tester.pumpAndSettle();
      expect(find.text('终端手机号必须是 12 位数字。'), findsOneWidget);
      expect(find.text('请输入 1 到 65535 之间的数值。'), findsOneWidget);
      expect(find.text('请输入 1–5 位大写字母或数字。'), findsOneWidget);
      expect(controller.terminals, isEmpty);
      await tester.enterText(_input('terminal-phone'), '013800138001');
      await tester.enterText(_input('terminal-port'), '8808');
      await tester.enterText(_input('terminal-manufacturer'), 'MARKS');
      await tester.enterText(_input('terminal-name'), 'My terminal');
      await tester.tap(find.byKey(const ValueKey('save-terminal')));
      await tester.pumpAndSettle();
      expect(controller.terminals.single.name, 'My terminal');
      expect(
        controller.runtime(controller.terminals.single.id).phase,
        ConnectionPhase.disconnected,
      );
      expect(controller.terminals.single.autoReconnect, isFalse);
      expect(find.text('My terminal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CSV requires explicit WGS84 and distinguishes example from road navigation',
    (tester) async {
      final controller = await _pump(tester, size: const Size(1440, 1000));
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text('新增线路').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('sim.routing.csv_tab')));
      await tester.pumpAndSettle();
      await tester.enterText(_input('route-name'), 'Test trajectory');
      await tester.enterText(_input('route-csv'), '39,116,40\n39.01,116.01,40');
      await tester.tap(find.text('保存线路'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CSV 首行必须为 # WGS84'), findsOneWidget);
      expect(controller.routes, isEmpty);
      final example = find.text('填入示例折线（非道路导航）');
      await tester.ensureVisible(example);
      await tester.tap(example);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存线路'));
      await tester.pumpAndSettle();
      expect(controller.routes.single.coordinateSystem, 'WGS84');
      expect(controller.routes.single.points.length, 5);
      expect(controller.routes.single.distanceKm, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failure persists across navigation and retry saves the in-memory workspace',
    (tester) async {
      final repository = _MemoryRepository()..failSave = true;
      final controller = await _pump(tester, repository: repository);
      await controller.saveTerminal(const TerminalConfig(id: 'test'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('save-failure-banner')), findsOneWidget);
      await _nav(tester, 'settings');
      expect(find.byKey(const ValueKey('save-failure-banner')), findsOneWidget);
      repository.failSave = false;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('save-failure-banner')), findsNothing);
      expect(repository.value.terminals.single.id, 'test');
    },
  );

  testWidgets(
    'load failure blocks creation and protects the repository until retry',
    (tester) async {
      final repository = _MemoryRepository(
        SimulatorWorkspace(terminals: const [TerminalConfig(id: 'existing')]),
      )..failLoad = true;
      final controller = await _pump(tester, repository: repository);
      expect(find.byKey(const ValueKey('load-failure')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('console-create-terminal')),
        findsNothing,
      );
      expect(repository.writes, 0);
      repository.failLoad = false;
      await tester.tap(find.text('重新读取'));
      await tester.pumpAndSettle();
      expect(controller.terminals.single.id, 'existing');
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(1100, 800),
    const Size(1440, 1000),
  ]) {
    for (final theme in ['light', 'dark']) {
      for (final language in ['zh', 'en']) {
        testWidgets(
          'populated views at ${size.width} in $theme / $language have no layout exception',
          (tester) async {
            final route = RouteCsv.parse(
              RouteCsv.example,
              id: 'route-1',
              name: 'WGS84 test polyline',
            );
            final workspace = SimulatorWorkspace(
              terminals: const [
                TerminalConfig(id: 'terminal-1', name: 'Terminal A'),
              ],
              routes: [route],
              tasks: const [
                DriveTask(
                  id: 'task-1',
                  name: 'Playback A',
                  terminalId: 'terminal-1',
                  routeId: 'route-1',
                ),
              ],
            );
            final controller = await _pump(
              tester,
              size: size,
              theme: theme,
              language: language,
              workspace: workspace,
            );
            expect(controller.onlineCount, 0);
            expect(controller.sentCount, 0);
            expect(controller.receivedCount, 0);
            expect(tester.takeException(), isNull);
            for (final page in [
              'terminals',
              'routes_tasks',
              'protocol_logs',
              'settings',
            ]) {
              await _nav(tester, page);
            }
          },
        );
      }
    }
  }

  testWidgets(
    'phone dialogs and manual flags stay usable in English dark mode',
    (tester) async {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
      await _pump(
        tester,
        theme: 'dark',
        language: 'en',
        workspace: SimulatorWorkspace(
          terminals: const [TerminalConfig(id: 't')],
          routes: [route],
        ),
      );
      await _nav(tester, 'terminals');
      await tester.tap(find.byKey(const ValueKey('create-terminal')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text('Add route').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save task'));
      await tester.pumpAndSettle();
      expect(find.text('Complete this field.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await _nav(tester, 'console');
      await tester.scrollUntilVisible(
        find.text('Manual position & flags'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual position & flags'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_input('location-status'));
      await tester.enterText(_input('location-status'), '100000000');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Use valid unsigned 32-bit HEX flags and check the mileage range.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workspace import validates before replacement and requires confirmation',
    (tester) async {
      final repository = _MemoryRepository(
        SimulatorWorkspace(terminals: const [TerminalConfig(id: 'keep')]),
      );
      final controller = await _pump(
        tester,
        repository: repository,
        size: const Size(1440, 1000),
      );
      await _nav(tester, 'settings');
      await tester.scrollUntilVisible(
        find.text('导入工作区 JSON'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SimPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入工作区 JSON'));
      await tester.pumpAndSettle();
      await tester.enterText(_input('workspace-json'), '{invalid');
      await tester.tap(find.text('检查并导入'));
      await tester.pumpAndSettle();
      expect(find.textContaining('工作区 JSON 无效或版本不受支持'), findsOneWidget);
      expect(controller.terminals.single.id, 'keep');
      expect(repository.writes, 0);
      await tester.enterText(
        _input('workspace-json'),
        jsonEncode(SimulatorWorkspace().toJson()),
      );
      await tester.tap(find.text('检查并导入'));
      await tester.pumpAndSettle();
      expect(find.text('确认覆盖本地工作区'), findsOneWidget);
      expect(find.textContaining('先断开全部终端'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.terminals.single.id, 'keep');
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty workspace actions stay with their explanation on desktop',
    (tester) async {
      await _pump(tester, size: const Size(1100, 720));
      final action = find.byKey(const ValueKey('console-create-terminal'));
      final message = find.text(tr('sim.no_terminals_console'));
      expect(
        tester.getTopLeft(action).dx,
        closeTo(tester.getTopLeft(message).dx, 1),
      );
      expect(
        tester.getTopLeft(action).dy,
        greaterThan(tester.getBottomLeft(message).dy),
      );
      await _nav(tester, 'terminals');
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('create-terminal')),
          matching: find.byType(SimEmpty),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'logs follow the current terminal and keep an explicit all filter on refresh',
    (tester) async {
      final controller =
          await _pump(
                tester,
                size: const Size(1100, 720),
                workspace: SimulatorWorkspace(
                  terminals: const [
                    TerminalConfig(
                      id: 'a',
                      name: 'Alpha',
                      phone: '013800138001',
                    ),
                    TerminalConfig(
                      id: 'b',
                      name: 'Beta',
                      phone: '013800138002',
                    ),
                  ],
                ),
                logs: [
                  ProtocolLog(
                    terminalId: 'a',
                    direction: LogDirection.sent,
                    message: 'Alpha-only packet',
                  ),
                  ProtocolLog(
                    terminalId: 'b',
                    direction: LogDirection.received,
                    message: 'Beta-only packet',
                  ),
                ],
              )
              as _LogController;
      await _nav(tester, 'protocol_logs');
      final filter = find.byKey(const ValueKey('log-terminal-filter'));
      expect(tester.widget<SimSelect<String>>(filter).value, 'a');
      expect(find.text('Alpha-only packet'), findsOneWidget);
      expect(find.text('Beta-only packet'), findsNothing);
      await _chooseSelect(tester, 'log-terminal-filter', 'Beta');
      expect(find.text('Alpha-only packet'), findsNothing);
      expect(find.text('Beta-only packet'), findsOneWidget);
      final sender = find.text(tr('sim.raw_send'));
      await tester.ensureVisible(sender);
      await tester.pumpAndSettle();
      await tester.tap(sender);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SimSelect<String>>(
              find.byKey(const ValueKey('raw-send-terminal')),
            )
            .value,
        'b',
      );
      await _chooseSelect(
        tester,
        'log-terminal-filter',
        tr('sim.all_terminals'),
      );
      expect(find.text('Alpha-only packet'), findsOneWidget);
      expect(find.text('Beta-only packet'), findsOneWidget);
      controller.addLog(
        ProtocolLog(
          terminalId: 'b',
          direction: LogDirection.event,
          message: 'Refresh without changing scope',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SimSelect<String>>(filter).value, '');
      await _chooseSelect(tester, 'raw-send-terminal', 'Alpha');
      expect(tester.widget<SimSelect<String>>(filter).value, 'a');
      expect(find.text('Beta-only packet'), findsNothing);
      await _nav(tester, 'console');
      await _nav(tester, 'protocol_logs');
      expect(tester.widget<SimSelect<String>>(filter).value, 'a');
      expect(find.text('Beta-only packet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1100, 720), const Size(390, 844)]) {
    testWidgets(
      'packet details scale to content at ${size.width} without changing copied HEX',
      (tester) async {
        final controller = await _pump(tester, size: size, language: 'en');
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final shortHex = Jt808Codec.toHex(
          const Jt808Codec().encode(
            Jt808Frame(messageId: 2, phone: '013800138000', sequence: 1),
          ),
        );
        final short = ProtocolLog(
          terminalId: 't',
          direction: LogDirection.sent,
          message: 'Heartbeat fixture',
          hex: shortHex,
        );
        final context = tester.element(find.byType(SimulatorScreen));
        unawaited(showLogDetail(context, controller, short));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ShadDialog>(find.byType(ShadDialog))
              .constraints
              ?.maxWidth,
          440,
        );
        final shortWidth = tester
            .getSize(find.byKey(const ValueKey('log-detail-content')))
            .width;
        await tester.tap(find.text(tr('sim.copy_hex')));
        await tester.pumpAndSettle();
        expect(copied, shortHex);
        ShadToaster.of(context).hide();
        await tester.tap(
          find
              .descendant(
                of: find.byType(ShadDialog),
                matching: find.byType(ShadIconButton),
              )
              .last,
        );
        await tester.pumpAndSettle();
        final longHex = Jt808Codec.toHex(
          const Jt808Codec().encode(
            Jt808Frame(
              messageId: 0x0900,
              phone: '013800138000',
              sequence: 2,
              body: List.filled(256, 0x12),
            ),
          ),
        );
        unawaited(
          showLogDetail(
            context,
            controller,
            ProtocolLog(
              terminalId: 't',
              direction: LogDirection.received,
              message: 'Long packet fixture',
              hex: longHex,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ShadDialog>(find.byType(ShadDialog))
              .constraints
              ?.maxWidth,
          680,
        );
        final longWidth = tester
            .getSize(find.byKey(const ValueKey('log-detail-content')))
            .width;
        expect(longWidth, lessThanOrEqualTo(size.width));
        if (size.width > 680) expect(longWidth, greaterThan(shortWidth));
        final displayed = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('log-detail-hex')),
            )
            .data!;
        expect(
          displayed.split('\n').every((line) => line.split(' ').length <= 16),
          isTrue,
        );
        expect(
          displayed.replaceAll(RegExp(r'\s'), ''),
          longHex.replaceAll(' ', ''),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final close in ['cancel', 'close', 'escape', 'barrier']) {
    testWidgets('dirty route editor protects $close and keeps the draft', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1100, 720));
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text(tr('sim.create_route')).first);
      await tester.pumpAndSettle();
      await tester.enterText(_input('route-name'), 'Draft route');
      switch (close) {
        case 'cancel':
          await tester.tap(find.text(tr('sim.cancel')));
        case 'close':
          await tester.tap(_dialogCloseIcon());
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'barrier':
          await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(find.text(tr('sim.discard_changes_title')), findsOneWidget);
      expect(find.byType(ShadDialog), findsNWidgets(2));
      await tester.tap(find.text(tr('sim.keep_editing')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_input('route-name')).controller.text,
        'Draft route',
      );
      await tester.tap(_dialogCloseIcon());
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('sim.discard_changes')));
      await tester.pumpAndSettle();
      expect(find.byType(ShadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'restoring a route draft to its initial value exits without a prompt',
    (tester) async {
      await _pump(tester, size: const Size(1100, 720));
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text(tr('sim.create_route')).first);
      await tester.pumpAndSettle();
      await tester.enterText(_input('route-name'), 'Temporary');
      await tester.enterText(_input('route-name'), '');
      await tester.tap(find.text(tr('sim.cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(ShadDialog), findsNothing);
      expect(find.text(tr('sim.discard_changes_title')), findsNothing);
    },
  );

  for (final editor in ['terminal', 'task', 'import']) {
    testWidgets('$editor editor protects unsaved input', (tester) async {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
      await _pump(
        tester,
        size: const Size(1100, 720),
        workspace: SimulatorWorkspace(
          terminals: const [TerminalConfig(id: 't')],
          routes: [route],
        ),
      );
      final String field;
      switch (editor) {
        case 'terminal':
          await _nav(tester, 'terminals');
          await tester.tap(find.byKey(const ValueKey('create-terminal')));
          field = 'terminal-name';
        case 'task':
          await _nav(tester, 'routes_tasks');
          await tester.tap(find.text(tr('sim.create_task')));
          field = 'task-name';
        default:
          await _nav(tester, 'settings');
          final importAction = find.text(tr('sim.import_workspace'));
          await tester.scrollUntilVisible(
            importAction,
            250,
            scrollable: find
                .descendant(
                  of: find.byType(SimPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(importAction);
          field = 'workspace-json';
      }
      await tester.pumpAndSettle();
      await tester.enterText(_input(field), 'Unsaved draft');
      await tester.tap(_dialogCloseIcon());
      await tester.pumpAndSettle();
      expect(find.text(tr('sim.discard_changes_title')), findsOneWidget);
      await tester.tap(find.text(tr('sim.keep_editing')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(_input(field)).controller.text,
        'Unsaved draft',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'saving blocks dismissal and successful save skips discard confirmation',
    (tester) async {
      final pending = Completer<void>();
      final repository = _MemoryRepository()..pendingSave = pending;
      await _pump(tester, size: const Size(1100, 720), repository: repository);
      await _nav(tester, 'terminals');
      await tester.tap(find.byKey(const ValueKey('create-terminal')));
      await tester.pumpAndSettle();
      await tester.enterText(_input('terminal-name'), 'Saved terminal');
      await tester.tap(find.byKey(const ValueKey('save-terminal')));
      await tester.pump();
      try {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.tapAt(const Offset(5, 5));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(ShadDialog), findsOneWidget);
        expect(find.text(tr('sim.discard_changes_title')), findsNothing);
        expect(
          tester.widget<ShadIconButton>(_dialogCloseIcon()).enabled,
          isFalse,
        );
      } finally {
        if (!pending.isCompleted) pending.complete();
      }
      await tester.pumpAndSettle();
      expect(repository.value.terminals.single.name, 'Saved terminal');
      expect(find.byType(ShadDialog), findsNothing);
      expect(find.text(tr('sim.discard_changes_title')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dialog scroll area stays below the close button and leaves header and actions fixed',
    (tester) async {
      await _pump(
        tester,
        size: DesktopWindowService.isSupported
            ? DesktopWindowService.minimumSize
            : const Size(390, 844),
      );
      await _nav(tester, 'terminals');
      await tester.tap(find.byKey(const ValueKey('create-terminal')));
      await tester.pumpAndSettle();
      final dialog = find.byType(ShadDialog);
      final title = find
          .descendant(
            of: dialog,
            matching: find.text(tr('sim.create_terminal')),
          )
          .first;
      final description = find.descendant(
        of: dialog,
        matching: find.text(tr('sim.dialog.terminal_description')),
      );
      final close = _dialogCloseIcon();
      final body = find
          .descendant(of: dialog, matching: find.byType(SingleChildScrollView))
          .first;
      final save = find.byKey(const ValueKey('save-terminal'));
      final closeBefore = tester.getRect(close);
      final titleBefore = tester.getRect(title);
      final descriptionBefore = tester.getRect(description);
      final saveBefore = tester.getRect(save);
      final fieldBefore = tester.getTopLeft(_input('terminal-name'));
      expect(
        tester.getRect(body).overlaps(closeBefore),
        isFalse,
        reason:
            'The scrollbar viewport must not enter the close-button hit area.',
      );
      expect(
        tester.getRect(body).top,
        greaterThanOrEqualTo(closeBefore.bottom),
      );
      expect(
        tester.getRect(body).top,
        greaterThanOrEqualTo(descriptionBefore.bottom),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: body, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(title), titleBefore);
      expect(tester.getRect(description), descriptionBefore);
      expect(tester.getRect(close), closeBefore);
      expect(tester.getRect(save), saveBefore);
      expect(
        tester.getTopLeft(_input('terminal-name')).dy,
        lessThan(fieldBefore.dy),
      );
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(ShadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'China default preview waits for own Key and creates two independent tile layers',
    (tester) async {
      final route = RouteCsv.parse(
        RouteCsv.example,
        id: 'cn',
        name: 'WGS84 route',
      );
      final original = jsonEncode(route.toJson());
      final controller = await _pump(
        tester,
        workspace: SimulatorWorkspace(routes: [route]),
      );
      await _nav(tester, 'routes_tasks');
      expect(find.byType(TileLayer), findsNothing);
      expect(
        find.byKey(const ValueKey('basemap-setup-required')),
        findsOneWidget,
      );
      expect(find.text(tr('sim.errors.tianditu_key_required')), findsOneWidget);
      final toggle = find.byKey(const ValueKey('preview-basemap-enabled'));
      expect(tester.widget<ShadSwitch>(toggle).value, isTrue);
      await controller.setBasemap(
        const BasemapSettings(tiandituKey: 'test-own-key'),
      );
      await tester.pumpAndSettle();
      final layers = tester
          .widgetList<TileLayer>(find.byType(TileLayer))
          .toList();
      expect(layers, hasLength(2));
      expect(layers[0].urlTemplate, contains('/vec_w/wmts?'));
      expect(layers[1].urlTemplate, contains('/cva_w/wmts?'));
      expect(layers[0].tileProvider, isNot(same(layers[1].tileProvider)));
      for (final layer in layers) {
        expect(layer.urlTemplate, contains('tk=test-own-key'));
        expect(layer.subdomains, ['0', '1', '2', '3', '4', '5', '6', '7']);
        expect(layer.maxNativeZoom, 18);
      }
      expect(
        find.byKey(const ValueKey('basemap-setup-required')),
        findsNothing,
      );
      expect(jsonEncode(controller.routes.single.toJson()), original);
      final line = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single;
      expect(
        line.points.first,
        LatLng(route.points.first.latitude, route.points.first.longitude),
      );
      await controller.setBasemap(
        controller.workspace.basemap.copyWith(tiandituKey: ''),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TileLayer), findsNothing);
      expect(tester.widget<ShadSwitch>(toggle).value, isTrue);
      expect(controller.workspace.basemap.provider, BasemapProvider.tianditu);
      expect(jsonEncode(controller.routes.single.toJson()), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'China default planning map keeps selection available without Key and has no overseas fallback',
    (tester) async {
      final planner = _FakeRoutePlanner();
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        planner: planner,
      );
      await _nav(tester, 'routes_tasks');
      await tester.tap(find.text(tr('sim.create_route')).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('planning-basemap-setup-required')),
        findsOneWidget,
      );
      expect(find.byType(TileLayer), findsNothing);
      expect(controller.workspace.basemap.enabled, isTrue);
      final mapFinder = find.descendant(
        of: find.byType(RoutePlanningMap),
        matching: find.byType(FlutterMap),
      );
      final center = tester.getRect(mapFinder).center;
      await tester.tapAt(center + const Offset(-35, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(center + const Offset(35, -15));
      await tester.pumpAndSettle();
      final selected = tester
          .widget<RoutePlanningMap>(find.byType(RoutePlanningMap))
          .waypoints;
      expect(selected, hasLength(2));
      final plan = find.byKey(const ValueKey('plan-route'));
      await tester.ensureVisible(plan);
      await tester.pumpAndSettle();
      await tester.tap(plan);
      await tester.pumpAndSettle();
      expect(planner.calls, 0);
      expect(find.text(tr('sim.errors.routing_key')), findsOneWidget);
      await controller.setBasemap(
        const BasemapSettings(tiandituKey: 'test-own-key'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TileLayer), findsNWidgets(2));
      expect(
        tester
            .widget<RoutePlanningMap>(find.byType(RoutePlanningMap))
            .waypoints,
        selected,
      );
      expect(controller.workspace.routing.provider, RoutingProvider.amap);
      expect(controller.workspace.routing.osrmUrl, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'domestic Key forms preserve switches and allow saving cleared credentials without planning',
    (tester) async {
      final planner = _FakeRoutePlanner();
      final repository = _MemoryRepository(
        SimulatorWorkspace(
          routing: const RoutePlanningSettings(amapKey: 'planning-original'),
        ),
      );
      final controller = await _pump(
        tester,
        size: const Size(1100, 900),
        repository: repository,
        planner: planner,
      );
      await _nav(tester, 'settings');
      Future<void> save(String id) async {
        final button = find.byKey(ValueKey(id));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> chooseBasemap(BasemapProvider provider) async {
        final select = find.byType(ShadSelect<BasemapProvider>);
        await tester.ensureVisible(select);
        await tester.pumpAndSettle();
        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(tr('sim.basemap_provider.${provider.name}')).last,
        );
        await tester.pumpAndSettle();
      }

      final basemapKey = _basemapInput('basemap-tianditu-key');
      await tester.ensureVisible(basemapKey);
      await tester.enterText(basemapKey, 'test-own-tianditu-key');
      expect(tester.widget<EditableText>(basemapKey).obscureText, isTrue);
      await chooseBasemap(BasemapProvider.openStreetMap);
      await chooseBasemap(BasemapProvider.tianditu);
      expect(
        tester.widget<EditableText>(basemapKey).controller.text,
        'test-own-tianditu-key',
      );
      await save('save-basemap');
      expect(repository.value.basemap.tiandituKey, 'test-own-tianditu-key');
      await tester.ensureVisible(basemapKey);
      await tester.enterText(basemapKey, 'bad key');
      await save('save-basemap');
      expect(find.text(tr('sim.errors.invalid_tianditu_key')), findsOneWidget);
      expect(repository.value.basemap.tiandituKey, 'test-own-tianditu-key');
      await tester.ensureVisible(basemapKey);
      await tester.enterText(basemapKey, '');
      await save('save-basemap');
      expect(repository.value.basemap.tiandituKey, isEmpty);
      expect(repository.value.basemap.provider, BasemapProvider.tianditu);
      for (final provider in [BasemapProvider.amap, BasemapProvider.baidu]) {
        await chooseBasemap(provider);
        final key = _basemapInput('basemap-${provider.name}-key');
        await tester.ensureVisible(key);
        await tester.enterText(key, 'tiles-${provider.name}');
        expect(tester.widget<EditableText>(key).obscureText, isTrue);
      }
      await chooseBasemap(BasemapProvider.amap);
      expect(
        tester
            .widget<EditableText>(_basemapInput('basemap-amap-key'))
            .controller
            .text,
        'tiles-amap',
      );
      await save('save-basemap');
      expect(repository.value.basemap.amapKey, 'tiles-amap');
      expect(repository.value.basemap.baiduKey, 'tiles-baidu');
      expect(repository.value.basemap.tiandituKey, isEmpty);
      expect(repository.value.basemap.amapUrl, isEmpty);
      expect(
        repository.value.basemap.configurationKey,
        'basemap_endpoint_required',
      );
      expect(repository.value.routing.amapKey, 'planning-original');
      for (final provider in [BasemapProvider.baidu, BasemapProvider.amap]) {
        await chooseBasemap(provider);
        final key = _basemapInput('basemap-${provider.name}-key');
        expect(
          tester.widget<EditableText>(key).controller.text,
          'tiles-${provider.name}',
        );
        await tester.ensureVisible(key);
        await tester.enterText(key, 'bad key');
        await save('save-basemap');
        expect(find.text(tr('sim.errors.invalid_basemap_key')), findsOneWidget);
        expect(repository.value.basemap.amapKey, 'tiles-amap');
        await tester.ensureVisible(key);
        await tester.enterText(key, '');
        await save('save-basemap');
        expect(repository.value.basemap.providerKey, isEmpty);
        expect(repository.value.routing.amapKey, 'planning-original');
      }
      expect(repository.value.basemap.amapKey, isEmpty);
      expect(repository.value.basemap.baiduKey, isEmpty);
      final routingKey = _basemapInput('routing-amap-key');
      await tester.ensureVisible(routingKey);
      await tester.pumpAndSettle();
      await tester.enterText(routingKey, 'test-own-amap-key');
      expect(tester.widget<EditableText>(routingKey).obscureText, isTrue);
      await save('save-routing');
      expect(repository.value.routing.amapKey, 'test-own-amap-key');
      await tester.ensureVisible(routingKey);
      await tester.enterText(routingKey, '');
      await save('save-routing');
      expect(repository.value.routing.amapKey, isEmpty);
      expect(repository.value.routing.osrmUrl, isEmpty);
      expect(repository.value.routing.provider, RoutingProvider.amap);
      expect(controller.workspace.basemap.enabled, isTrue);
      expect(find.byType(TileLayer), findsNothing);
      expect(planner.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'optional provider Keys and endpoints gate layers without mutating templates',
    (tester) async {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
      final controller = await _pump(
        tester,
        workspace: SimulatorWorkspace(routes: [route]),
      );
      await _nav(tester, 'routes_tasks');
      for (final provider in [
        BasemapProvider.openStreetMap,
        BasemapProvider.amap,
        BasemapProvider.baidu,
      ]) {
        final pending = BasemapSettings(
          provider: provider,
          amapKey: 'amap-key',
          baiduKey: 'baidu-key',
        );
        await controller.setBasemap(pending);
        await tester.pumpAndSettle();
        expect(find.byType(TileLayer), findsNothing);
        expect(
          find.text(tr('sim.errors.basemap_endpoint_required')),
          findsOneWidget,
        );
        const template = 'https://tiles.example.com/{z}/{x}/{y}.png?key={key}';
        if (provider != BasemapProvider.openStreetMap) {
          final missingKey = pending.copyWith(
            amapUrl: template,
            baiduUrl: template,
            amapKey: '',
            baiduKey: '',
          );
          await controller.setBasemap(missingKey);
          await tester.pumpAndSettle();
          expect(find.byType(TileLayer), findsNothing);
          expect(
            find.text(tr('sim.errors.basemap_key_required')),
            findsOneWidget,
          );
          final ready = missingKey.copyWith(
            amapKey: 'amap&safe',
            baiduKey: 'baidu+safe',
          );
          await controller.setBasemap(ready);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
            ready.tileUrl,
          );
          expect(controller.workspace.basemap.tileTemplate, template);
          expect(
            controller.workspace.basemap.toJson()[provider ==
                    BasemapProvider.amap
                ? 'amapUrl'
                : 'baiduUrl'],
            template,
          );
        } else {
          await controller.setBasemap(
            pending.copyWith(osmUrl: 'https://osm.example.com/{z}/{x}/{y}.png'),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
            'https://osm.example.com/{z}/{x}/{y}.png',
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit OpenStreetMap switch persists across navigation', (
    tester,
  ) async {
    final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
    final controller = await _pump(
      tester,
      workspace: SimulatorWorkspace(
        routes: [route],
        basemap: const BasemapSettings(
          provider: BasemapProvider.openStreetMap,
          osmUrl: BasemapSettings.legacyOsmUrl,
        ),
      ),
    );
    await _nav(tester, 'routes_tasks');
    expect(find.byType(FlutterMap), findsOneWidget);
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(
      layer.tileProvider.headers['User-Agent'],
      contains('com.marks.flutter_jtt808_simulator'),
    );
    expect(find.text('© OpenStreetMap 贡献者'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('preview-basemap-enabled'));
    expect(tester.widget<ShadSwitch>(toggle).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: toggle, matching: find.byType(ShadFocusable)),
    );
    await tester.pumpAndSettle();
    expect(controller.workspace.basemap.enabled, isFalse);
    expect(find.byType(FlutterMap), findsNothing);
    await _nav(tester, 'settings');
    expect(
      tester
          .widget<ShadSwitch>(
            find.byKey(const ValueKey('basemap-default-enabled')),
          )
          .value,
      isFalse,
    );
    await _nav(tester, 'routes_tasks');
    expect(tester.widget<ShadSwitch>(toggle).value, isFalse);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets(
    'tile failure is temporary and stale errors cannot cancel a retry',
    (tester) async {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
      final controller = await _pump(
        tester,
        workspace: SimulatorWorkspace(
          routes: [route],
          basemap: const BasemapSettings(
            provider: BasemapProvider.openStreetMap,
            osmUrl: BasemapSettings.legacyOsmUrl,
          ),
        ),
      );
      await _nav(tester, 'routes_tasks');
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      final tile = TileImage(
        vsync: tester,
        coordinates: const TileCoordinates(790, 294, 12),
        imageProvider: MemoryImage(TileProvider.transparentImage),
        onLoadComplete: (_) {},
        onLoadError: (_, _, _) {},
        tileDisplay: const TileDisplay.instantaneous(),
        errorImage: null,
        cancelLoading: Completer<void>(),
      );
      addTearDown(tile.dispose);
      layer.errorTileCallback!(
        tile,
        StateError('test tile error'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsNothing);
      expect(controller.workspace.basemap.enabled, isTrue);
      final retry = find.byKey(const ValueKey('retry-basemap'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
        isNot(same(layer.tileProvider)),
      );
      layer.errorTileCallback!(
        tile,
        StateError('late error'),
        StackTrace.current,
      );
      await tester.pumpAndSettle();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-basemap')), findsNothing);
    },
  );

  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets(
        'keyless presets change drafts only and persist independent fields at ${size.width} in $theme',
        (tester) async {
          final seeded = theme == 'dark';
          final original = SimulatorWorkspace(
            theme: theme,
            basemap: BasemapSettings(
              tiandituKey: seeded ? 'retained-tianditu' : '',
              amapKey: seeded ? 'retained-tiles-amap' : '',
              baiduKey: seeded ? 'retained-baidu' : '',
              amapUrl: seeded ? 'https://amap.example/{z}/{x}/{y}.png' : '',
              baiduUrl: seeded ? 'https://baidu.example/{z}/{x}/{y}.png' : '',
              customUrl: seeded ? 'https://custom.example/{z}/{x}/{y}.png' : '',
              customAttribution: seeded ? 'Retained attribution' : '',
              customCoordinates: seeded
                  ? BasemapCoordinates.gcj02
                  : BasemapCoordinates.wgs84,
            ),
            routing: RoutePlanningSettings(
              amapKey: seeded ? 'retained-routing-amap' : '',
              amapAuthorized: seeded,
            ),
          );
          final repository = _MemoryRepository(original);
          final planner = _FakeRoutePlanner();
          final controller = await _pump(
            tester,
            size: size,
            theme: theme,
            language: 'en',
            repository: repository,
            planner: planner,
          );
          await _nav(tester, 'settings');
          expect(
            controller.workspace.basemap.provider,
            BasemapProvider.tianditu,
          );
          expect(controller.workspace.basemap.osmUrl, isEmpty);
          expect(controller.workspace.routing.provider, RoutingProvider.amap);
          expect(controller.workspace.routing.osrmUrl, isEmpty);
          expect(repository.writes, 0);

          Future<void> tap(String key) async {
            final button = find.byKey(ValueKey(key));
            await _revealSettings(tester, button);
            await tester.tap(button);
            await tester.pumpAndSettle();
          }

          Future<void> chooseBasemap(BasemapProvider provider) async {
            final select = find.byType(ShadSelect<BasemapProvider>);
            await _revealSettings(tester, select);
            await tester.tap(select);
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(tr('sim.basemap_provider.${provider.name}')).last,
            );
            await tester.pumpAndSettle();
          }

          Future<void> chooseRouting(RoutingProvider provider) async {
            final select = find.byType(ShadSelect<RoutingProvider>);
            await _revealSettings(tester, select);
            await tester.tap(select);
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(tr('sim.routing.provider.${provider.name}')).last,
            );
            await tester.pumpAndSettle();
          }

          await tap('use-public-imagery');
          final osmInput = _basemapInput('basemap-tile-url');
          expect(
            tester.widget<EditableText>(osmInput).controller.text,
            BasemapSettings.publicImageryUrl,
          );
          expect(
            find.byKey(const PageStorageKey('basemap-tianditu-key')),
            findsNothing,
          );
          expect(
            find.byKey(const PageStorageKey('basemap-amap-key')),
            findsNothing,
          );
          expect(
            find.byKey(const PageStorageKey('basemap-baidu-key')),
            findsNothing,
          );
          expect(repository.value.basemap, original.basemap);
          expect(controller.workspace.basemap, original.basemap);
          expect(repository.writes, 0);
          expect(planner.calls, 0);
          expect(find.byType(TileLayer), findsNothing);
          await tap('save-basemap');
          final savedBasemap = original.basemap.copyWith(
            provider: BasemapProvider.custom,
            customUrl: BasemapSettings.publicImageryUrl,
            customCoordinates: BasemapCoordinates.wgs84,
            customAttribution: BasemapSettings.publicImageryAttribution,
          );
          expect(repository.value.basemap, savedBasemap);
          expect(repository.value.basemap.configurationKey, isNull);
          expect(repository.writes, 1);

          // Both explicit public routing presets work without consulting Amap.
          for (final preset in [
            (key: 'use-public-osrm', url: RoutePlanningSettings.publicDemoUrl),
            (
              key: 'use-fossgis-osrm',
              url: RoutePlanningSettings.fossgisDemoUrl,
            ),
          ]) {
            final before = repository.value.routing;
            final writes = repository.writes;
            await tap(preset.key);
            final routingInput = _basemapInput('routing-osrm-url');
            await _revealSettings(tester, routingInput);
            expect(
              tester.widget<EditableText>(routingInput).controller.text,
              preset.url,
            );
            expect(
              find.byKey(const PageStorageKey('routing-amap-key')),
              findsNothing,
            );
            expect(repository.value.routing, before);
            expect(controller.workspace.routing, before);
            expect(repository.writes, writes);
            expect(planner.calls, 0);
            await tap('save-routing');
            expect(
              repository.value.routing,
              original.routing.copyWith(
                provider: RoutingProvider.osrm,
                osrmUrl: preset.url,
              ),
            );
            expect(repository.value.routing.planningValidationKey, isNull);
            expect(repository.writes, writes + 1);
          }

          // Switching back restores domestic fields, not a preset's empty keys.
          await chooseRouting(RoutingProvider.amap);
          final amapInput = _basemapInput('routing-amap-key');
          await _revealSettings(tester, amapInput);
          expect(
            tester.widget<EditableText>(amapInput).controller.text,
            original.routing.amapKey,
          );
          final authorized = find.byKey(
            const ValueKey('routing-amap-authorized'),
          );
          await _revealSettings(tester, authorized);
          expect(
            tester.widget<ShadCheckbox>(authorized).value,
            original.routing.amapAuthorized,
          );
          await tap('save-routing');
          expect(repository.value.routing.amapKey, original.routing.amapKey);
          expect(
            repository.value.routing.amapAuthorized,
            original.routing.amapAuthorized,
          );
          expect(
            repository.value.routing.osrmUrl,
            RoutePlanningSettings.fossgisDemoUrl,
          );
          await chooseBasemap(BasemapProvider.tianditu);
          final domesticInput = _basemapInput('basemap-tianditu-key');
          await _revealSettings(tester, domesticInput);
          expect(
            tester.widget<EditableText>(domesticInput).controller.text,
            original.basemap.tiandituKey,
          );
          await tap('save-basemap');
          expect(
            repository.value.basemap,
            savedBasemap.copyWith(provider: BasemapProvider.tianditu),
          );

          await tester.pump(const Duration(seconds: 8));
          await tester.pumpAndSettle();
          await _nav(tester, 'console');
          await _nav(tester, 'settings');
          await chooseBasemap(BasemapProvider.custom);
          expect(
            tester.widget<EditableText>(osmInput).controller.text,
            BasemapSettings.publicImageryUrl,
          );
          await chooseRouting(RoutingProvider.osrm);
          final routingInput = _basemapInput('routing-osrm-url');
          await _revealSettings(tester, routingInput);
          expect(
            tester.widget<EditableText>(routingInput).controller.text,
            RoutePlanningSettings.fossgisDemoUrl,
          );
          final reloaded = SimulatorController(repository);
          await reloaded.load();
          expect(reloaded.workspace.toJson(), repository.value.toJson());
          reloaded.dispose();
          expect(repository.writes, 5);
          expect(planner.calls, 0);
          expect(find.byType(TileLayer), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [const Size(390, 844), const Size(1100, 900)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets(
        'basemap settings validate and keep per-source URLs at ${size.width} in $theme',
        (tester) async {
          final controller = await _pump(
            tester,
            size: size,
            theme: theme,
            language: 'en',
          );
          await _nav(tester, 'settings');
          Future<void> choose(String text) async {
            final select = find.byType(ShadSelect<BasemapProvider>);
            await tester.ensureVisible(select);
            await tester.pumpAndSettle();
            await tester.tap(select);
            await tester.pumpAndSettle();
            await tester.tap(find.text(text).last);
            await tester.pumpAndSettle();
          }

          Future<void> save() async {
            final button = find.byKey(const ValueKey('save-basemap'));
            // The save action is now in the card header. Finish the text
            // field's pending reveal before scrolling back up to that header.
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await Scrollable.ensureVisible(
              tester.element(button),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            await tester.tap(button);
            await tester.pumpAndSettle();
          }

          await choose(tr('sim.basemap_provider.amap'));
          await save();
          expect(controller.workspace.basemap.provider, BasemapProvider.amap);
          expect(
            controller.workspace.basemap.configurationKey,
            'basemap_endpoint_required',
          );
          const amapUrl = 'https://amap.example.com/{z}/{x}/{y}.png?key={key}';
          final amapKey = _basemapInput('basemap-amap-key');
          await tester.ensureVisible(amapKey);
          expect(tester.widget<EditableText>(amapKey).obscureText, isTrue);
          await tester.enterText(amapKey, 'amap&encoded');
          await tester.enterText(_basemapInput('basemap-tile-url'), amapUrl);
          await save();
          expect(controller.workspace.basemap.amapUrl, amapUrl);
          expect(controller.workspace.basemap.amapKey, 'amap&encoded');
          expect(
            controller.workspace.basemap.tileUrl,
            contains('key=amap%26encoded'),
          );
          expect(controller.workspace.routing.amapKey, isEmpty);
          await choose(tr('sim.basemap_provider.baidu'));
          expect(
            tester
                .widget<EditableText>(_basemapInput('basemap-tile-url'))
                .controller
                .text,
            isEmpty,
          );
          const baiduUrl =
              'https://baidu.example.com/{z}/{x}/{y}.png?key={key}';
          final baiduKey = _basemapInput('basemap-baidu-key');
          await tester.ensureVisible(baiduKey);
          expect(tester.widget<EditableText>(baiduKey).obscureText, isTrue);
          await tester.enterText(baiduKey, 'baidu-own-key');
          await tester.enterText(_basemapInput('basemap-tile-url'), baiduUrl);
          await save();
          expect(controller.workspace.basemap.baiduUrl, baiduUrl);
          expect(controller.workspace.basemap.baiduKey, 'baidu-own-key');
          expect(controller.workspace.basemap.amapKey, 'amap&encoded');
          await choose(tr('sim.basemap_provider.amap'));
          expect(
            tester
                .widget<EditableText>(_basemapInput('basemap-tile-url'))
                .controller
                .text,
            amapUrl,
          );
          expect(
            tester.widget<EditableText>(amapKey).controller.text,
            'amap&encoded',
          );
          await choose(tr('sim.basemap_provider.openStreetMap'));
          expect(
            find.byKey(const PageStorageKey('basemap-amap-key')),
            findsNothing,
          );
          expect(
            find.byKey(const PageStorageKey('basemap-baidu-key')),
            findsNothing,
          );
          await save();
          expect(controller.workspace.basemap.osmUrl, isEmpty);
          expect(
            controller.workspace.basemap.configurationKey,
            'basemap_endpoint_required',
          );
          const osmUrl = 'https://osm.example.com/{z}/{x}/{y}.png';
          await tester.enterText(_basemapInput('basemap-tile-url'), osmUrl);
          await save();
          expect(controller.workspace.basemap.osmUrl, osmUrl);
          expect(controller.workspace.basemap.configurationKey, isNull);
          await tester.enterText(_basemapInput('basemap-tile-url'), '');
          await save();
          expect(controller.workspace.basemap.osmUrl, isEmpty);
          expect(
            controller.workspace.basemap.configurationKey,
            'basemap_endpoint_required',
          );
          await choose(tr('sim.basemap_provider.custom'));
          await save();
          expect(controller.workspace.basemap.provider, BasemapProvider.custom);
          expect(controller.workspace.basemap.customAttribution, isEmpty);
          expect(
            controller.workspace.basemap.configurationKey,
            'basemap_endpoint_required',
          );
          await tester.enterText(
            _basemapInput('basemap-tile-url'),
            'http://tiles.example.com/{z}/{x}/{y}.png',
          );
          await tester.enterText(
            _basemapInput('basemap-custom-attribution'),
            '© Test source',
          );
          await save();
          expect(controller.workspace.basemap.provider, BasemapProvider.custom);
          expect(
            find.text(tr('sim.errors.invalid_basemap_url')),
            findsOneWidget,
          );
          const customUrl =
              'https://tiles.example.com/{z}/{x}/{y}.png?token=test';
          await tester.enterText(_basemapInput('basemap-tile-url'), customUrl);
          final coordinates = find.byType(ShadSelect<BasemapCoordinates>);
          await tester.ensureVisible(coordinates);
          await tester.pumpAndSettle();
          await tester.tap(coordinates);
          await tester.pumpAndSettle();
          await tester.tap(find.text('GCJ-02').last);
          await tester.pumpAndSettle();
          await save();
          expect(controller.workspace.basemap.provider, BasemapProvider.custom);
          expect(
            controller.workspace.basemap.customCoordinates,
            BasemapCoordinates.gcj02,
          );
          expect(controller.workspace.basemap.customUrl, customUrl);
          expect(controller.workspace.basemap.amapUrl, amapUrl);
          expect(controller.workspace.basemap.baiduUrl, baiduUrl);
          await tester.pump(const Duration(seconds: 8));
          await tester.pumpAndSettle();
          await _nav(tester, 'console');
          await _nav(tester, 'settings');
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const PageStorageKey('basemap-tile-url')),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<EditableText>(_basemapInput('basemap-tile-url'))
                .controller
                .text,
            customUrl,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'changing the source updates the displayed coordinates, not the saved route',
    (tester) async {
      final route = RouteCsv.parse(RouteCsv.example, id: 'r', name: 'Route');
      final original = jsonEncode(route.toJson());
      final controller = await _pump(
        tester,
        workspace: SimulatorWorkspace(routes: [route]),
      );
      await _nav(tester, 'routes_tasks');
      await controller.setBasemap(
        const BasemapSettings(
          provider: BasemapProvider.amap,
          amapUrl: 'https://amap.example.com/{z}/{x}/{y}.png',
        ),
      );
      await tester.pumpAndSettle();
      final polyline = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single;
      expect(
        polyline.points.first,
        isNot(
          LatLng(route.points.first.latitude, route.points.first.longitude),
        ),
      );
      expect(jsonEncode(controller.routes.single.toJson()), original);
      expect(find.text('© 高德地图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'English and Chinese translations contain the same complete simulator keys',
    (tester) async {
      Map<String, Object?> flatten(
        Map<String, Object?> map, [
        String prefix = '',
      ]) => {
        for (final entry in map.entries)
          if (entry.value is Map)
            ...flatten(
              Map<String, Object?>.from(entry.value as Map),
              '$prefix${entry.key}.',
            )
          else
            '$prefix${entry.key}': entry.value,
      };
      final en = _english;
      final zh = _chinese;
      final english = flatten(Map<String, Object?>.from(en['sim']! as Map));
      final chinese = flatten(Map<String, Object?>.from(zh['sim']! as Map));
      expect(english.keys.toSet(), chinese.keys.toSet());
      expect(
        english.values.every((value) => value is String && value.isNotEmpty),
        isTrue,
      );
      expect(
        chinese.values.every((value) => value is String && value.isNotEmpty),
        isTrue,
      );
      expect(en.keys.toSet(), {'window', 'sim'});
      expect(zh.keys.toSet(), en.keys.toSet());
    },
  );
}
