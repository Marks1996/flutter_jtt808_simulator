import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/route_preview.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/widgets/sim_ui.dart';

late Map<String, dynamic> _english;
late Map<String, dynamic> _chinese;

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

class _TestApp extends ConsumerWidget {
  const _TestApp();

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
          builder: (context, child) => ShadAppBuilder(child: child!),
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
        overrides: [simulatorProvider.overrideWith((ref) => controller)],
        child: const _TestApp(),
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

Finder _dialogCloseIcon() => find.byKey(const ValueKey('dialog-close'));

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
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
            expect(tester.getSize(nav).height, 34);
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
        lessThanOrEqualTo(640),
      );
      await tester.tap(_input('route-csv'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('route-name'));
      final before = tester.getSize(field);
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
          await tester.tap(find.text(tr('sim.import_workspace')));
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
