import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../extensions/context_extension.dart';
import '../../../../theme/theme_constants.dart';
import '../../../../utils/platform_info.dart';
import '../providers/simulator_provider.dart';

export 'package:shadcn_ui/shadcn_ui.dart';
export '../../../../extensions/context_extension.dart';
export '../../../../theme/theme_constants.dart';
export '../../../../utils/async_state.dart';
export '../../../../utils/failure.dart';

/// Compact 4-point rhythm for the simulator, independent of window size.
/// Preserve readable type and touch targets; tighten space between groups.
abstract final class SimSpace {
  static double get xs => AppSpacing.xs;
  static double get sm => AppSpacing.xs;
  static double get ms => AppSpacing.sm;
  static double get md => AppSpacing.ms;
  static double get lg => AppSpacing.md;
  static double get xl => AppSpacing.lg;
}

abstract final class SimStyle {
  static const sectionRadius = AppBorders.card;
  static const controlRadius = BorderRadius.all(Radius.circular(6));
  static const double pageInset = 16;
  static const double controlHeight = 32;
  static const double touchHeight = 44;
  static const double contentWidth = 1200;
}

TextStyle? simNumberStyle(BuildContext context) => context.textTheme.bodyMedium
    ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle? simCodeStyle(BuildContext context) => simNumberStyle(
  context,
)?.copyWith(fontFamily: 'IBM Plex Mono', fontSize: 12);

String simHex(int value, [int width = 8]) =>
    '0x${value.toRadixString(16).padLeft(width, '0').toUpperCase()}';

String simTime(DateTime time) => DateFormat('HH:mm:ss.SSS').format(time);

String simError(Object error) {
  final key = error is FormatException ? error.message : '';
  const keys = {
    'required',
    'invalid_port',
    'invalid_phone',
    'invalid_region',
    'invalid_identity',
    'invalid_plate',
    'invalid_interval',
    'invalid_coordinates',
    'invalid_motion',
    'invalid_flags',
    'disconnect_before_edit',
    'duplicate_phone',
    'terminal_in_use',
    'stop_before_edit',
    'route_in_use',
    'task_dependencies',
    'connect_first',
    'terminal_task_busy',
    'disconnect_before_import',
    'route_coordinate_header',
    'route_point_count',
    'route_csv_invalid',
    'route_zero_length',
    'invalid_hex',
    'invalid_workspace',
    'file_unreadable',
    'invalid_theme',
    'invalid_tianditu_key',
    'tianditu_key_required',
    'invalid_basemap_key',
    'basemap_endpoint_required',
    'basemap_key_required',
    'invalid_basemap',
    'invalid_basemap_url',
    'basemap_attribution_required',
    'routing_amap_authorization',
    'routing_rate',
    'routing_settings',
    'routing_url',
    'routing_key',
    'routing_points',
    'routing_stale',
    'routing_response',
    'routing_no_route',
    'routing_network',
    'routing_limit',
    'routing_cancelled',
  };
  return tr('sim.errors.${keys.contains(key) ? key : 'operation_failed'}');
}

Future<void> simRun(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ShadToaster.of(
        context,
      ).show(ShadToast.destructive(description: Text(simError(error))));
    }
  }
}

Future<void> simCopy(BuildContext context, String text) async {
  await simRun(context, () async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ShadToaster.of(
        context,
      ).show(ShadToast(description: Text(tr('sim.copied'))));
    }
  });
}

/// File selection is a UI operation. Read only the picker-provided bytes: no
/// filesystem path access, storage database, or network client in widgets.
Future<String?> simPickText({required List<String> extensions}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
    allowMultiple: false,
    withData: true,
  );
  if (result == null) return null;
  final Uint8List? bytes = result.files.single.bytes;
  if (bytes == null || bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('file_unreadable');
  }
  return utf8.decode(bytes).replaceFirst('\uFEFF', '');
}

Future<bool> simConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String? confirm,
  String? cancel,
  bool destructive = false,
}) async =>
    await showShadDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: Text(title),
        description: Text(body),
        constraints: BoxConstraints(
          maxWidth: 512,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .9,
        ),
        titlePinned: true,
        descriptionPinned: true,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancel ?? tr('sim.cancel')),
          ),
          if (destructive)
            ShadButton.destructive(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirm ?? tr('sim.delete')),
            )
          else
            ShadButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirm ?? tr('sim.delete')),
            ),
        ],
      ),
    ) ??
    false;

class SimButton extends StatelessWidget {
  const SimButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.destructive = false,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary, destructive, loading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = context.textTheme.labelLarge!;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final naturalWidth =
          painter.width +
          SimSpace.ms * 2 +
          (icon != null || loading ? 22 : 0) +
          2;
      painter.dispose();
      final width = constraints.hasBoundedWidth
          ? math.min(naturalWidth, constraints.maxWidth)
          : naturalWidth;
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: PlatformInfo.isDesktop
              ? SimStyle.controlHeight
              : SimStyle.touchHeight,
        ),
        child: ShadButton.raw(
          variant: destructive
              ? ShadButtonVariant.destructive
              : primary
              ? ShadButtonVariant.primary
              : ShadButtonVariant.outline,
          width: width,
          height: 0,
          expands: true,
          textStyle: style,
          enabled: onPressed != null && !loading,
          onPressed: onPressed,
          padding: EdgeInsets.symmetric(horizontal: SimSpace.ms, vertical: 6),
          leading: loading
              ? const SizedBox(width: 16, child: ShadProgress(minHeight: 2))
              : icon == null
              ? null
              : Icon(icon, size: 14),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );
    },
  );
}

class SimIconButton extends StatelessWidget {
  const SimIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ShadTooltip(
    builder: (_) => Text(tooltip),
    child: Semantics(
      container: true,
      label: tooltip,
      child: ShadButton.ghost(
        width: PlatformInfo.isDesktop ? 32 : 44,
        height: PlatformInfo.isDesktop ? 32 : 44,
        padding: EdgeInsets.zero,
        enabled: onPressed != null,
        onPressed: onPressed,
        child: icon,
      ),
    ),
  );
}

class SimTextButton extends StatelessWidget {
  const SimTextButton({super.key, required this.child, this.onPressed});
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ShadButton.ghost(
      size: ShadButtonSize.sm,
      height: 0,
      expands: constraints.hasBoundedWidth,
      padding: EdgeInsets.symmetric(horizontal: SimSpace.ms, vertical: 6),
      enabled: onPressed != null,
      onPressed: onPressed,
      child: child,
    ),
  );
}

class SimListRow extends StatelessWidget {
  const SimListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.dense = false,
  });
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ShadButton.ghost(
          height: 0,
          expands: true,
          mainAxisAlignment: MainAxisAlignment.start,
          padding: contentPadding ?? EdgeInsets.all(SimSpace.ms),
          onPressed: onTap,
          leading: leading,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: dense ? 40 : 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [title, ?subtitle],
            ),
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class SimExpansion extends StatelessWidget {
  const SimExpansion({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.tilePadding,
    this.childrenPadding,
  });
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry? tilePadding, childrenPadding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: tilePadding ?? EdgeInsets.symmetric(horizontal: SimSpace.md),
    child: ShadAccordion<String>(
      children: [
        ShadAccordionItem<String>(
          value: 'content',
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, ?subtitle],
          ),
          child: Padding(
            padding: childrenPadding ?? EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

class SimPage extends StatelessWidget {
  const SimPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    required this.children,
    this.maxWidth = SimStyle.contentWidth,
  });
  final String title, subtitle;
  final List<Widget> actions, children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // SafeArea consumes this inset on mobile. On desktop the viewport
    // reaches the window edge, while only its initial content is inset.
    final topInset = MediaQuery.paddingOf(context).top;
    final scrollView = ListView(
      key: PageStorageKey(title),
      padding: EdgeInsets.fromLTRB(
        SimStyle.pageInset,
        SimStyle.pageInset + topInset,
        SimStyle.pageInset,
        SimStyle.pageInset,
      ),
      children: [
        for (final section in [
          SimPageHeader(title: title, subtitle: subtitle, actions: actions),
          SizedBox(height: SimSpace.lg),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) SizedBox(height: SimSpace.md),
          ],
        ])
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SizedBox(width: double.infinity, child: section),
            ),
          ),
      ],
    );
    if (topInset == 0) return scrollView;
    final surface = context.colors.surface;
    return Stack(
      children: [
        Positioned.fill(child: scrollView),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topInset + SimStyle.pageInset,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                key: const ValueKey('sim-titlebar-fade'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      surface,
                      surface.withValues(alpha: .9),
                      surface.withValues(alpha: 0),
                    ],
                    stops: const [0, .4, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SimPageHeader extends StatelessWidget {
  const SimPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });
  final String title, subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.headlineLarge),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: SimSpace.xs),
            Text(
              subtitle,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
      if (constraints.maxWidth < 720 || actions.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (actions.isNotEmpty) ...[
              SizedBox(height: SimSpace.md),
              Wrap(
                spacing: SimSpace.sm,
                runSpacing: SimSpace.sm,
                children: actions,
              ),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          SizedBox(width: SimSpace.lg),
          Wrap(
            spacing: SimSpace.sm,
            runSpacing: SimSpace.sm,
            children: actions,
          ),
        ],
      );
    },
  );
}

class SimPanel extends StatelessWidget {
  const SimPanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = true,
  });
  final String? title, subtitle;
  final Widget? trailing;
  final Widget child;
  final bool padding;

  @override
  Widget build(BuildContext context) => ShadCard(
    backgroundColor: context.colors.surfaceContainerLow,
    border: ShadBorder.all(color: context.colors.outlineVariant),
    radius: SimStyle.sectionRadius,
    padding: EdgeInsets.zero,
    columnCrossAxisAlignment: CrossAxisAlignment.stretch,
    shadows: const [],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: SimSpace.lg,
              vertical: SimSpace.md,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: context.textTheme.titleMedium),
                      if (subtitle != null) ...[
                        SizedBox(height: SimSpace.xs),
                        Text(
                          subtitle!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: SimSpace.ms),
                  trailing!,
                ],
              ],
            ),
          ),
        Padding(
          padding: padding ? EdgeInsets.all(SimSpace.lg) : EdgeInsets.zero,
          child: child,
        ),
      ],
    ),
  );
}

class SimEmpty extends StatelessWidget {
  const SimEmpty({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.textTheme.titleSmall),
        SizedBox(height: SimSpace.xs),
        Text(
          message,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: SimSpace.ms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: context.colors.onSurfaceVariant),
          ),
          SizedBox(width: SimSpace.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                if (action != null) ...[SizedBox(height: SimSpace.ms), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SimNotice extends StatelessWidget {
  const SimNotice({
    super.key,
    required this.text,
    this.error = false,
    this.action,
  });
  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) => error
      ? ShadAlert.destructive(
          icon: const Icon(Icons.error_outline, size: 18),
          description: Text(text),
          descriptionStyle: context.textTheme.bodySmall,
          iconPadding: EdgeInsets.only(right: SimSpace.ms),
          decoration: ShadDecoration(
            border: ShadBorder(padding: EdgeInsets.all(SimSpace.ms)),
          ),
          trailing: action,
        )
      : ShadAlert(
          icon: const Icon(Icons.info_outline, size: 18),
          description: Text(text),
          descriptionStyle: context.textTheme.bodySmall,
          iconPadding: EdgeInsets.only(right: SimSpace.ms),
          decoration: ShadDecoration(
            border: ShadBorder(padding: EdgeInsets.all(SimSpace.ms)),
          ),
          trailing: action,
        );
}

class SimPhase extends StatelessWidget {
  const SimPhase(this.phase, {super.key});
  final ConnectionPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      ConnectionPhase.online => context.appColors.success,
      ConnectionPhase.failed => context.colors.error,
      ConnectionPhase.connecting ||
      ConnectionPhase.registering ||
      ConnectionPhase.authenticating => context.appColors.warning,
      ConnectionPhase.disconnected => context.colors.onSurfaceVariant,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 7),
        SizedBox(width: SimSpace.sm),
        Flexible(
          child: Text(
            tr('sim.phase.${phase.name}'),
            style: context.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

ShadDecoration _inputDecoration(BuildContext context) => ShadDecoration(
  disableSecondaryBorder: true,
  labelStyle: context.textTheme.bodySmall?.copyWith(
    fontWeight: FontWeight.w500,
  ),
  labelPadding: const EdgeInsets.only(bottom: 4),
  descriptionStyle: context.textTheme.bodySmall,
  descriptionPadding: const EdgeInsets.only(top: 4),
  color: context.colors.surfaceContainerLowest,
  border: ShadBorder.all(
    color: context.colors.outline,
    width: 1,
    radius: SimStyle.controlRadius,
    padding: EdgeInsets.zero,
  ),
  focusedBorder: ShadBorder.all(
    color: context.colors.primary,
    width: 1,
    radius: SimStyle.controlRadius,
    padding: EdgeInsets.zero,
  ),
  errorBorder: ShadBorder.all(
    color: context.colors.error,
    width: 1,
    radius: SimStyle.controlRadius,
    padding: EdgeInsets.zero,
  ),
);

class SimField extends StatelessWidget {
  const SimField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.hint,
    this.helper,
    this.obscure = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.keyboardType,
    this.suffix,
    this.compact = false,
  });
  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final String? hint, helper;
  final bool obscure, enabled, compact;
  final int maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => Semantics(
    container: compact,
    label: compact ? label : null,
    child: ShadInputFormField(
      key: PageStorageKey('input-$label'),
      controller: controller,
      validator: validator == null ? null : (value) => validator!(value),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      label: compact ? null : Text(label),
      placeholder: Text(hint ?? (compact ? label : '')),
      decoration: _inputDecoration(context),
      description: helper == null ? null : Text(helper!),
      obscureText: obscure,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: simNumberStyle(context),
      trailing: suffix,
      padding: EdgeInsets.symmetric(horizontal: SimSpace.ms, vertical: 6),
    ),
  );
}

/// Select data is independent of Material dropdown widgets.
class SimOption<T> {
  const SimOption({required this.value, required this.child});
  final T value;
  final Widget child;
}

class SimSelect<T> extends StatelessWidget {
  const SimSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.compact = false,
  });
  final String label;
  final T? value;
  final List<SimOption<T>> items;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    container: compact,
    label: compact ? label : null,
    child: LayoutBuilder(
      builder: (context, constraints) => ShadSelectFormField<T>(
        key: ValueKey((label, value)),
        initialValue: value,
        label: compact ? null : Text(label),
        placeholder: Text(label),
        decoration: _inputDecoration(context),
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
        options: items.map(
          (item) => ShadOption<T>(value: item.value, child: item.child),
        ),
        selectedOptionBuilder: (context, selected) =>
            items.firstWhere((item) => item.value == selected).child,
        onChanged: onChanged,
        enabled: onChanged != null,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        padding: EdgeInsets.symmetric(horizontal: SimSpace.ms, vertical: 6),
      ),
    ),
  );
}

class SimFieldGrid extends StatelessWidget {
  const SimFieldGrid({super.key, required this.children, this.minWidth = 220});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          ((constraints.maxWidth + SimSpace.md) / (minWidth + SimSpace.md))
              .floor()
              .clamp(1, children.length.clamp(1, 3));
      final width =
          (constraints.maxWidth - SimSpace.md * (columns - 1)) / columns;
      return Wrap(
        spacing: SimSpace.md,
        runSpacing: SimSpace.md,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

/// Guards user-initiated pop requests (Cancel, close, Escape and barrier).
/// A successful save deliberately uses Navigator.pop to leave without a prompt.
class SimEditGuard extends StatefulWidget {
  const SimEditGuard({
    super.key,
    required this.hasChanges,
    required this.child,
    this.isSaving,
  });
  final bool Function() hasChanges;
  final bool Function()? isSaving;
  final Widget child;

  @override
  State<SimEditGuard> createState() => _SimEditGuardState();
}

class _SimEditGuardState extends State<SimEditGuard> {
  bool _confirming = false;

  Future<void> _requestClose() async {
    if (_confirming || (widget.isSaving?.call() ?? false)) return;
    _confirming = true;
    try {
      final discard =
          !widget.hasChanges() ||
          await simConfirm(
            context,
            title: tr('sim.discard_changes_title'),
            body: tr('sim.discard_changes_body'),
            cancel: tr('sim.keep_editing'),
            confirm: tr('sim.discard_changes'),
            destructive: true,
          );
      if (discard && mounted) Navigator.of(context).pop();
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_requestClose());
    },
    child: widget.child,
  );
}

class SimKeyValue extends StatelessWidget {
  const SimKeyValue(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: SimSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(width: SimSpace.md),
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: simNumberStyle(context),
          ),
        ),
      ],
    ),
  );
}

String? simRequired(String? value) =>
    value == null || value.trim().isEmpty ? tr('sim.errors.required') : null;
String? simIntRange(String? value, int min, int max) {
  final number = int.tryParse(value ?? '');
  return number == null || number < min || number > max
      ? tr('sim.number_range', namedArgs: {'min': '$min', 'max': '$max'})
      : null;
}

String? simDoubleRange(String? value, double min, double max) {
  final number = double.tryParse(value ?? '');
  return number == null || !number.isFinite || number < min || number > max
      ? tr('sim.number_range', namedArgs: {'min': '$min', 'max': '$max'})
      : null;
}
