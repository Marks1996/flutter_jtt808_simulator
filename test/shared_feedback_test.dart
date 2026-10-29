import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter_jtt808_simulator/src/routing/global_navigator.dart';
import 'package:flutter_jtt808_simulator/src/shared/helpers/show_toast.dart';
import 'package:flutter_jtt808_simulator/src/theme/shad_theme.dart';

void main() {
  test('shared feedback is safe before the navigator is mounted', () {
    expect(() => showGlobalToast(message: 'Ready'), returnsNormally);
  });

  for (final status in ['success', 'error']) {
    testWidgets('shared $status feedback uses the library toast', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShadApp.custom(
          theme: buildShadLightTheme(primaryColorHex: '#204bc3'),
          darkTheme: buildShadDarkTheme(primaryColorHex: '#204bc3'),
          appBuilder: (context) => MaterialApp(
            navigatorKey: rootNavigatorKey,
            localizationsDelegates: const [GlobalShadLocalizations.delegate],
            builder: (context, child) => ShadAppBuilder(child: child!),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      showGlobalToast(message: 'Operation $status', status: status);
      await tester.pumpAndSettle();

      expect(find.byType(ShadToast), findsOneWidget);
      expect(find.text('Operation $status'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
