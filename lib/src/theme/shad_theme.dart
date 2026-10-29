import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../utils/platform_info.dart';
import 'theme.dart';

ShadColorScheme _mapColorScheme(ColorScheme scheme) => ShadColorScheme(
  background: scheme.surfaceContainerLowest,
  foreground: scheme.onSurface,
  card: scheme.surfaceContainerLow,
  cardForeground: scheme.onSurface,
  popover: scheme.surfaceContainerLowest,
  popoverForeground: scheme.onSurface,
  primary: scheme.onSurface,
  primaryForeground: scheme.surfaceContainerLowest,
  secondary: scheme.surfaceContainerHigh,
  secondaryForeground: scheme.onSurface,
  muted: scheme.surfaceContainer,
  mutedForeground: scheme.onSurfaceVariant,
  accent: scheme.surfaceContainerHighest,
  accentForeground: scheme.onSurface,
  destructive: scheme.error,
  destructiveForeground: scheme.onError,
  border: scheme.outlineVariant,
  input: scheme.outline,
  ring: scheme.primary,
  selection: scheme.primary.withValues(alpha: .15),
);

ShadThemeData _workbenchTheme(ThemeData material) {
  final text = material.textTheme;
  // The macOS page inset protects native traffic lights. A centered dialog
  // already clears that strip and must not repeat its inset inside the header.
  final dialogTheme = ShadDialogTheme(useSafeArea: !PlatformInfo.isMacOS);
  return ShadThemeData(
    brightness: material.brightness,
    primaryDialogTheme: dialogTheme,
    alertDialogTheme: dialogTheme,
    colorScheme: _mapColorScheme(material.colorScheme),
    radius: const BorderRadius.all(Radius.circular(6)),
    textTheme: ShadTextTheme(
      family: 'IBM Plex Sans',
      h1: text.headlineSmall,
      h2: text.titleLarge,
      h3: text.titleMedium,
      h4: text.titleSmall,
      p: text.bodyMedium,
      table: text.bodyMedium,
      list: text.bodyMedium,
      lead: text.bodyLarge,
      small: text.labelLarge,
      muted: ShadTextTheme(
        family: 'IBM Plex Sans',
      ).muted.copyWith(fontWeight: text.bodySmall?.fontWeight),
    ).apply(fontFamilyFallback: text.bodyMedium?.fontFamilyFallback),
  );
}

ShadThemeData buildShadLightTheme({required String primaryColorHex}) =>
    _workbenchTheme(buildLightTheme(primaryColorHex: primaryColorHex));

ShadThemeData buildShadDarkTheme({required String primaryColorHex}) =>
    _workbenchTheme(buildDarkTheme(primaryColorHex: primaryColorHex));
