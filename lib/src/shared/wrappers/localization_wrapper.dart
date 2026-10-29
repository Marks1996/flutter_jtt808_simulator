import '../../imports/core_imports.dart';

/// A wrapper to initialize [EasyLocalization] with supported locales.
class LocalizationWrapper extends StatelessWidget {
  final Widget child;

  const LocalizationWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      startLocale: const Locale('zh'),
      useOnlyLangCode: true,
      fallbackLocale: const Locale('en'),
      child: child,
    );
  }
}
