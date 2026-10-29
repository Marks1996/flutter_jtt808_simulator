import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/color_schemes.dart';
import '../theme/theme.dart';

extension ContextExtension on BuildContext {
  // ── Theme shortcuts ──────────────────────────────────────────────────────
  ThemeData get theme => Theme.of(this);
  TextTheme get typography => theme.textTheme;
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colors => theme.colorScheme;
  bool get isDarkMode => theme.brightness == Brightness.dark;

  /// Semantic/custom colors (success, warning, info).
  AppColorsExtension get appColors =>
      theme.extension<AppColorsExtension>() ??
      (isDarkMode ? AppPalettes.dark : AppPalettes.light);

  /// Design tokens (spacing, border radii, elevation defaults).
  AppDesignTokens get designTokens =>
      theme.extension<AppDesignTokens>() ?? AppDesignTokens.fallback;

  // ── MediaQuery shortcuts ─────────────────────────────────────────────────
  Size get mediaQuerySize => MediaQuery.sizeOf(this);
  Size get screenSize => mediaQuerySize;
  double get width => mediaQuerySize.width;
  double get height => mediaQuerySize.height;

  /// Safe-area insets for the current view.
  EdgeInsets get safeArea => MediaQuery.paddingOf(this);

  // ── Keyboard ──────────────────────────────────────────────────────────────
  bool get isKeyboardVisible => MediaQuery.viewInsetsOf(this).bottom > 0;
  void hideKeyboard() => FocusScope.of(this).unfocus();

  // ── Platform ─────────────────────────────────────────────────────────────
  bool get isIOS => theme.platform == TargetPlatform.iOS;
  bool get isAndroid => theme.platform == TargetPlatform.android;

  // ── Routing shortcuts ────────────────────────────────────────────────────
  String get currentRoute {
    final router = GoRouter.of(this);
    final RouteMatch lastMatch =
        router.routerDelegate.currentConfiguration.last;
    final RouteMatchList matchList = lastMatch is ImperativeRouteMatch
        ? lastMatch.matches
        : router.routerDelegate.currentConfiguration;
    return matchList.uri.toString();
  }
}
