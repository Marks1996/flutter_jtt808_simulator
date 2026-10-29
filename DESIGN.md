# Design system — flutter_jtt808_simulator

This file documents the design conventions established at generation time. Consult it before changing UI code.

---

## Theme overview

- **Preset:** `material3`
- **Material 3:** Primary app chrome uses Material 3 theming in `lib/src/theme/theme.dart`.
- **Dark mode:** Light and dark themes are supported; app can follow system brightness. Use semantic colors — do not branch on brightness in widgets for basic surfaces.
- **Customization:** Global `ThemeData` lives in `lib/src/theme/theme.dart` — avoid one-off `ThemeData` overrides in feature widgets.

- **Seed color:** `#204bc3` (used to derive `ColorScheme` via `ColorScheme.fromSeed` where applicable).

---

## Color system

- Use `context.colors` (`ColorScheme`) for standard Material roles: `primary`, `onPrimary`, `secondary`, `surface`, `onSurface`, `error`, etc.
- Use `context.appColors` for semantic extensions: `success`, `warning`, `info`, and their `on*` / container variants (see `lib/src/theme/color_schemes.dart`).
- Definitions: `lib/src/theme/color_schemes.dart`, applied through `lib/src/theme/theme.dart`.
- **Do not** hardcode hex colors in widgets — use theme roles or `appColors`.

---

## Typography

- Use `context.textTheme` (alias `context.typography`) for all text styles.
- Roles follow Material 3: `display*`, `headline*`, `title*`, `body*`, `label*`.
- IBM Plex Sans is bundled for UI text. `chinese_font_library` supplies the system Chinese fallback chain, with Microsoft YaHei first on Windows. Windows body and small-label roles use weight 500; other platforms retain weight 400. Material and all shadcn roles share the fallback chain. Flutter maps `fontWeight` to variable-font axes automatically; do not pin a `wght` variation on base styles, because later `copyWith(fontWeight: ...)` must remain effective. Fonts load locally without runtime downloads. IBM Plex Mono remains reserved for protocol identifiers and HEX. Both bundled font families and their SIL Open Font License live under `assets/fonts/`.

---

## Spacing, borders, motion

Import tokens via `package:flutter_jtt808_simulator/src/theme/theme_constants.dart`.

| Token class | Purpose |
|-------------|---------|
| `AppSpacing` | Padding, gaps (`xxs` … `xxxl`, plus `pagePadding`, `itemGap`, `cardPadding`) |
| `AppBorders` | Border radii (`xs` … `xl`, `button`, `card`, `input`, `dialog`, …) |
| `AppShadows` | Elevation shadows (`none`, `subtle`, `card`, `elevated`, `modal`) |
| `AppDurations` | Animation durations (`fast`, `normal`, `medium`, `slow`, …) |
| `AppCurves` | Standard curves (`standard`, `emphasized`, `pageEnter`, …) |

**Rules**

- Do not use magic numbers for padding — use `AppSpacing`.
- Do not use inline `BorderRadius.circular(n)` — use `AppBorders`.
- Prefer Material 3 tonal elevation on `Card` / `Surface` — custom shadows only via `AppShadows`.

---

## Responsive scaling (ScreenUtil)

- `ScreenUtilInit` is already applied in the app wrapper — do not add another.
- Design size baseline: **390×844**.
- This is a native operations tool: ScreenUtil scaling is disabled in `ScreenUtilWrapper` so `.w`, `.h`, `.r`, `.sp` stay logical-pixel sized on desktop and mobile. Adapt columns/navigation by available width; retain operating-system text scaling for accessibility.
- Existing spacing tokens and component APIs remain the source of truth; do not add per-screen scale overrides.

---

## Context extensions

Defined in `lib/src/extensions/context_extension.dart`:

| Member | Use |
|--------|-----|
| `context.colors` | `ColorScheme` |
| `context.textTheme` / `context.typography` | Text styles |
| `context.appColors` | Semantic success/warning/info |
| `context.designTokens` | Theme extension tokens |
| `context.isDarkMode` | Brightness check |
| `context.width` / `context.height` | Screen size |

Prefer these shortcuts over repeating `Theme.of(context)` in widgets.

---

## Component conventions

- Reusable widgets belong in `lib/src/shared/widgets/`.
- Default style parameters to theme values, not hardcoded colors.
- Widget file names match the widget class (`primary_button.dart` → `PrimaryButton`).
- Do not read theme inside `const` constructors.

### Dark mode checklist

- No raw `Colors.white` / `Colors.black` for surfaces — use `colorScheme` roles.
- Verify new screens in both light and dark theme.

---

## Localization

- User-visible strings use `easy_localization` — files in `assets/translations/`.
- Do not hardcode display strings in widgets.
- Add keys to JSON translation files, then run the generate command in **SETUP.md**.
- Use interpolation in JSON — do not concatenate translated strings in Dart.

---

## Do / Don't

**Do**

- `context.colors` / `context.appColors` for color
- `context.textTheme` for typography
- `AppSpacing`, `AppBorders`, `AppShadows`, `AppDurations`, `AppCurves` for layout and motion
- Direct `shadcn_ui` components and business-specific compositions for consistent UX

---

## UI component library

Interactive simulator UI uses `package:shadcn_ui/shadcn_ui.dart` directly.

- Use the library's `ShadButton`, `ShadCard`, form fields, dialogs, toasts and other components without a mirrored `App*` / `ShadApp*` API.
- The redundant `shared/widgets/ui` kit and component gallery have been removed. Do not recreate them or add Dialog wrappers/aliases.
- Shared theme integration lives in `lib/src/theme/shad_theme.dart`: `buildShadLightTheme` / `buildShadDarkTheme` preserve the Material color and typography mapping.
- Reusable simulator compositions and business behavior live under `features/simulator/presentation/widgets`. Cross-feature widgets belong in `shared/widgets`, for example the native desktop window frame.
- Feedback uses `ShadToaster` / `ShadToast`; shared operations without a widget context use `showGlobalToast`, which delegates to the same library components.
- The only application route is the local simulator. Login, registration, onboarding, the placeholder home page and their mock-account state are outside the product and have been removed.

### Design tokens (required)

```dart
AppSpacing.md
AppBorders.card
AppShadows.elevated
AppDurations.normal
AppCurves.standard
context.colors.primary
context.appColors.success
context.textTheme.titleMedium
context.designTokens.paddingMedium
```

**Never** hardcode hex colors or magic spacing numbers in feature UI.

---

**Don't**

- Hardcode hex colors or arbitrary font families in widgets
- Magic padding/radius numbers
- Duplicate theme definitions per screen
- Bypass design tokens for one-off “quick” UI

For agent workflows and architecture boundaries, see **[AGENTS.md](AGENTS.md)**.

## Simulator operating interface

The simulator applies the Impeccable Operate and Taste app-screen guidance to the existing blue Material/shadcn system. This is a technical tool, not a marketing page: use real terminal objects, true zero states, clear units, fixed logical control sizes and native feedback.

- Native desktop platforms always retain labelled desktop navigation. Startup size and native minimum size are both 1100×720; a narrow resize callback never switches desktop into phone navigation. Android/iOS layouts can use a navigation rail at tablet widths and a bottom bar on phones.
- Compact operating density: 16px page gutters, 12px panel/form gaps, 8px control padding, 4px inline gaps. Page headings use `titleLarge`, panel headings use `titleSmall`; body type and system text scaling remain unchanged. Desktop actions use small shadcn buttons; mobile retains larger touch targets.
- Labelled sidebar is 184px wide with approximately 34px navigation rows. Sidebar labels explicitly align left instead of inheriting `ShadButton`'s centered text. Navigation uses actual multi-part, gradient SVG artwork from Microsoft Fluent Color, vendored under `assets/icons/navigation/`, rather than recolored Material glyphs. Render the source colors unchanged with `SvgPicture.asset` and no color filter or color mapper, at 20px on the sidebar/rail and 22px on the phone bottom bar. The source version and MIT notice live beside the assets in `SOURCE.md` and `LICENSE`. Selected/hover surfaces remain neutral and selected semantics remain available. Bottom-bar labels remain centered. The macOS invisible drag strip is 32px high; native traffic lights remain visible. Windows/Linux caption height is 32px with no bottom divider. Windows shows the app identity in the caption only, with no repeated sidebar header. Debug settings offer a session-only macOS/Windows chrome preview without changing native platform behavior.
- Form grids use at most the number of actual fields. Logs grow from their real record count rather than reserving a fixed-height empty region. Empty-state actions sit directly below their explanation at all widths; terminal management uses its header action only after records exist.
- Packet detail dialogs adapt to HEX length: compact 440px, medium 560px, large 680px, bounded by the viewport. Labels stay in a nearby 112px column, and display HEX uses 16 bytes per line in IBM Plex Mono. Copy actions preserve the original HEX and JSON data.
- Entering logs inherits the current terminal. An explicit All selection survives ordinary log refreshes. Changing the filter to a specific terminal updates the current terminal and send target; changing the send terminal also updates the log scope.
- Business dialogs follow `shadcn_ui`'s shipped `example/lib/pages/dialog.dart`: call `showShadDialog`, then return `ShadDialog` or `ShadDialog.alert` directly. Use the library's `title`, `description`, `child` and `actions` slots, default padding/gaps, default `large`/`muted` header styles, and regular `ShadButton` footer variants. Keep IBM Plex fonts and semantic app colors. Do not add project-specific Dialog/View wrappers, hand-built title bars or per-dialog visual overrides. Pin both title and description so the library scrolls only the content; actions retain their default fixed behavior. Edit dialogs use `ShadIconButton` with the library's default size, position, colors and hover appearance, but use `maybePop` so their independent `SimEditGuard` protects drafts. The macOS theme disables the dialog's internal SafeArea because the native drag-strip page inset must not be repeated inside the centered modal; other platforms retain the library safe-area behavior. Packet details keep their content-based widths and two copy actions, using the library's X rather than a redundant third footer button.
- Terminal, route, task and workspace-import drafts are protected on Cancel, the dialog close button, Escape and the modal barrier. Prompt only when current values differ from their original values. While saving, closing is disabled; a successful save exits directly without a discard prompt.
- Blue `primary` is reserved for principal actions, selection and the actual route; semantic colors indicate connection and errors. Light content panels use `surfaceContainerLow` over `surfaceContainerLowest`; dark surfaces use the same roles. Shadcn `secondary` and `accent` map to neutral surface-container roles rather than Material's colored secondary/tertiary roles, keeping selected navigation and hover states readable in both themes.
- Reusable simulator UI lives in `features/simulator/presentation/widgets`. Interactive components use `shadcn_ui`: `ShadButton`, `ShadCard`, `ShadInputFormField`, `ShadSelectFormField`, `ShadDialog`, `ShadAlert`, `ShadToast`, `ShadAccordion`, `ShadCheckbox`, `ShadSwitch` and `ShadProgress`. Use shared spacing/radii and compact dimensions; preserve Flutter's `Form` validation infrastructure without falling back to Material-styled fields or buttons. Text fields carry distinct PageStorage keys.
- The console is scoped to one terminal. Connection controls precede location, task and recent messages; editing is progressive disclosure. Task-controlled movement fields are locked while alarm/status flags remain editable.
- Defaults are illustrative and unsaved until the operator creates a terminal. The production workspace starts empty, with no auto-connect or fake data.
- Current verification: 113 tests passed with Flutter 3.47.8. Navigation regressions verify left-aligned labels, actual local Fluent Color SVG assets with multiple source colors and gradients, the bundled Microsoft MIT notice, and no color filter/mapper across light/dark themes and all selected pages. Existing dialog, real-app platform/header, shared-toast, log-scope, HEX-copy and draft/save-protection regressions remain passing. Two additional temporary rendering tests passed and produced light/dark navigation previews with bundled fonts; the historical images have since been removed. Those checks provided widget-rendering evidence, not native system-window screenshots. The temporary rendering entry point was removed. Static analysis and the macOS Debug build passed. Historical dialog/platform notes remain in `docs/VERIFICATION.md` and `docs/SESSION_HANDOFF.md`; this does not imply a new Windows/Linux native build or a VoiceOver audit.
