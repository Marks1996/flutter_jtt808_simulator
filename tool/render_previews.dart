// Optional visual review harness. It never starts a network session or writes a
// real workspace. Run with SIMULATOR_PREVIEW_FONT set to a local CJK font and
// `fvm flutter test tool/render_previews.dart --update-goldens`.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/providers/simulator_provider.dart';
import 'package:flutter_jtt808_simulator/src/features/simulator/presentation/screens/simulator_screen.dart';
import 'package:flutter_jtt808_simulator/src/theme/shad_theme.dart';
import 'package:flutter_jtt808_simulator/src/theme/theme.dart';

class _Repository implements SimulatorRepository {
  _Repository(this.data);
  SimulatorWorkspace data;
  @override
  Future<SimulatorWorkspace> load() async => data;
  @override
  Future<void> save(SimulatorWorkspace workspace) async {
    data = workspace;
  }
}

class _PreviewAssets extends AssetLoader {
  const _PreviewAssets(this.translations);
  final Map<String, dynamic> translations;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      translations;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> translations;
  final font = Platform.environment['SIMULATOR_PREVIEW_FONT'];
  setUpAll(() async {
    if (font == null) {
      throw StateError(
        'Set SIMULATOR_PREVIEW_FONT to a local CJK TTF for readable previews.',
      );
    }
    final bytes = await File(font).readAsBytes();
    await (FontLoader(
      'PreviewSans',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    translations = Map<String, dynamic>.from(
      jsonDecode(await File('assets/translations/zh.json').readAsString())
          as Map,
    );
    // This opt-in entry point is executed by flutter_test, but lives outside
    // test/ so normal test runs do not depend on a machine-local font file.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableBuildModes = [];
    await EasyLocalization.ensureInitialized();
  });
  for (final (name, size) in [
    ('desktop', const Size(1440, 1000)),
    ('tablet', const Size(768, 1024)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final dark in [false, true]) {
      for (final populated in [false, true]) {
        testWidgets(
          '$name ${dark ? 'dark' : 'light'} ${populated ? 'console' : 'empty'}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final route = RouteCsv.parse(
              RouteCsv.example,
              id: 'example',
              name: '示例折线（非道路导航）',
            );
            final controller = SimulatorController(
              _Repository(
                SimulatorWorkspace(
                  terminals: populated
                      ? const [
                          TerminalConfig(
                            id: 't',
                            name: '联调终端 01',
                            plate: '京A12345',
                          ),
                        ]
                      : [],
                  routes: populated ? [route] : [],
                  tasks: populated
                      ? const [
                          DriveTask(
                            id: 'task',
                            name: '坐标轨迹回放',
                            terminalId: 't',
                            routeId: 'example',
                          ),
                        ]
                      : [],
                ),
              ),
            );
            await controller.load();
            final material = dark
                ? buildDarkTheme(primaryColorHex: '#204bc3')
                : buildLightTheme(primaryColorHex: '#204bc3');
            final shad = dark
                ? buildShadDarkTheme(primaryColorHex: '#204bc3')
                : buildShadLightTheme(primaryColorHex: '#204bc3');
            await tester.pumpWidget(
              EasyLocalization(
                supportedLocales: const [Locale('zh'), Locale('en')],
                path: 'assets/translations',
                assetLoader: _PreviewAssets(translations),
                startLocale: const Locale('zh'),
                fallbackLocale: const Locale('zh'),
                saveLocale: false,
                child: ProviderScope(
                  overrides: [
                    simulatorProvider.overrideWith((ref) => controller),
                  ],
                  child: ScreenUtilInit(
                    enableScaleWH: () => false,
                    enableScaleText: () => false,
                    builder: (context, _) => ShadApp.custom(
                      theme: shad.copyWith(
                        textTheme: ShadTextTheme(family: 'PreviewSans'),
                      ),
                      appBuilder: (context) => MaterialApp(
                        debugShowCheckedModeBanner: false,
                        theme: material.copyWith(
                          textTheme: material.textTheme.apply(
                            fontFamily: 'PreviewSans',
                          ),
                        ),
                        localizationsDelegates: [
                          GlobalShadLocalizations.delegate,
                          ...context.localizationDelegates,
                        ],
                        supportedLocales: context.supportedLocales,
                        locale: context.locale,
                        builder: (context, child) =>
                            ShadAppBuilder(child: child!),
                        home: const RepaintBoundary(
                          key: ValueKey('preview'),
                          child: SimulatorScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('preview')),
              matchesGoldenFile(
                '../output/previews/$name-${dark ? 'dark' : 'light'}-${populated ? 'console' : 'empty'}.png',
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      }
    }
  }
}
