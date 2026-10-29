import 'package:flutter_jtt808_simulator/src/imports/core_imports.dart';
import 'package:flutter_jtt808_simulator/src/imports/packages_imports.dart';
import 'features/simulator/presentation/providers/simulator_provider.dart';
import 'shared/widgets/desktop_window_frame.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(simulatorProvider).workspace.theme;
    final mode = switch (preference) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ScreenUtilWrapper(
      child: ShadApp.custom(
        themeMode: mode,
        theme: buildShadLightTheme(primaryColorHex: '#204bc3'),
        darkTheme: buildShadDarkTheme(primaryColorHex: '#204bc3'),
        appBuilder: (context) => MaterialApp.router(
          title: 'JT/T808 模拟器',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(primaryColorHex: '#204bc3'),
          darkTheme: buildDarkTheme(primaryColorHex: '#204bc3'),
          themeMode: mode,
          routerConfig: appRouter,
          localizationsDelegates: [
            GlobalShadLocalizations.delegate,
            ...context.localizationDelegates,
          ],
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          builder: (context, child) =>
              ShadAppBuilder(child: DesktopWindowFrame(child: child!)),
        ),
      ),
    );
  }
}
