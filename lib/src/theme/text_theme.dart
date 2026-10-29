import 'package:flutter/material.dart';

/// A restrained operating typescale, shared by Material infrastructure and
/// shadcn controls. CJK uses the installed native sans face; Plex is bundled.
TextTheme buildTextTheme() {
  TextStyle role(double size, FontWeight weight, [double height = 1.4]) =>
      TextStyle(
        fontFamily: 'IBM Plex Sans',
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
        ],
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
      );
  return TextTheme(
    displayLarge: role(32, FontWeight.w600, 1.2),
    displayMedium: role(28, FontWeight.w500, 1.2),
    displaySmall: role(24, FontWeight.w500, 1.25),
    headlineLarge: role(24, FontWeight.w600, 1.25),
    headlineMedium: role(22, FontWeight.w600, 1.3),
    headlineSmall: role(20, FontWeight.w600, 1.3),
    titleLarge: role(20, FontWeight.w600, 1.3),
    titleMedium: role(14, FontWeight.w600),
    titleSmall: role(13, FontWeight.w500),
    bodyLarge: role(14, FontWeight.w400, 1.5),
    bodyMedium: role(13, FontWeight.w400, 1.45),
    bodySmall: role(12, FontWeight.w400, 1.45),
    labelLarge: role(13, FontWeight.w500),
    labelMedium: role(12, FontWeight.w500),
    labelSmall: role(11, FontWeight.w400),
  );
}
