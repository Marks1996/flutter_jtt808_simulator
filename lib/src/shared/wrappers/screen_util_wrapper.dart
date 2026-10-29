import '../../imports/imports.dart';

/// A wrapper to initialize [ScreenUtil] with design-specific constraints.
class ScreenUtilWrapper extends StatelessWidget {
  final Widget child;
  final Size designSize;
  final bool minTextAdapt;
  final bool splitScreenMode;

  const ScreenUtilWrapper({
    super.key,
    required this.child,
    this.designSize = const Size(390, 844),
    this.minTextAdapt = true,
    this.splitScreenMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: designSize,
      minTextAdapt: minTextAdapt,
      splitScreenMode: splitScreenMode,
      // An operations tool adapts its columns, not the physical size of controls.
      // Keep legacy .w/.h/.sp tokens stable on desktop and retain OS text scaling.
      enableScaleWH: () => false,
      enableScaleText: () => false,
      builder: (context, _) => child,
    );
  }
}
