import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/protocol/jt808_codec.dart';
import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

Future<void> showLogDetail(
  BuildContext context,
  SimulatorController controller,
  ProtocolLog log,
) => showShadDialog<void>(
  context: context,
  builder: (_) => _LogDetail(controller: controller, log: log),
);

class _LogDetail extends StatelessWidget {
  const _LogDetail({required this.controller, required this.log});
  final SimulatorController controller;
  final ProtocolLog log;

  @override
  Widget build(BuildContext context) {
    // Reuse the protocol's strict decoder only for display. Never infer header
    // fields from a terminal configuration that may have changed since capture.
    Jt808Frame? frame;
    Object? decodeError;
    if (log.hex.isNotEmpty) {
      try {
        frame = const Jt808Codec().decode(Jt808Codec.parseHex(log.hex));
      } catch (error) {
        decodeError = error;
      }
    }
    final terminal = controller.terminals
        .where((t) => t.id == log.terminalId)
        .firstOrNull;
    final json = const JsonEncoder.withIndent('  ').convert({
      'time': log.time.toIso8601String(),
      'terminalId': log.terminalId,
      'direction': log.direction.name,
      'messageId': log.idHex,
      'sequence': log.sequence,
      'message': log.message,
      'hex': log.hex,
      'error': log.isError,
    });
    final hexLength = log.hex.replaceAll(RegExp(r'\s'), '').length;
    final width = hexLength > 256
        ? 680.0
        : hexLength > 96
        ? 560.0
        : 440.0;
    return ShadDialog(
      title: Text(tr('sim.log_detail')),
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      titlePinned: true,
      descriptionPinned: true,
      description: Text(tr('sim.dialog.log_description')),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actions: [
        ShadButton.outline(
          leading: const Icon(Icons.copy_outlined, size: 16),
          onPressed: () => simCopy(context, json),
          child: Text(tr('sim.copy_json')),
        ),
        ShadButton(
          enabled: log.hex.isNotEmpty,
          onPressed: log.hex.isEmpty ? null : () => simCopy(context, log.hex),
          child: Text(tr('sim.copy_hex')),
        ),
      ],
      child: Column(
        key: const ValueKey('log-detail-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailValue(tr('sim.time'), log.time.toIso8601String()),
          _DetailValue(tr('sim.terminal'), terminal?.name ?? log.terminalId),
          _DetailValue(
            tr('sim.direction'),
            tr('sim.log_direction.${log.direction.name}'),
          ),
          _DetailValue(
            tr('sim.message_id'),
            frame == null ? log.idHex : simHex(frame.messageId, 4),
          ),
          _DetailValue(
            tr('sim.sequence'),
            '${frame?.sequence ?? log.sequence ?? '—'}',
          ),
          if (frame != null) ...[
            _DetailValue(tr('sim.field.phone'), frame.phone),
            _DetailValue(
              tr('sim.body_length'),
              tr(
                'sim.byte_count',
                namedArgs: {'count': '${frame.body.length}'},
              ),
            ),
            _DetailValue(tr('sim.header_validation'), tr('sim.header_valid')),
          ],
          SizedBox(height: SimSpace.md),
          SelectableText(log.message, style: context.textTheme.bodyMedium),
          if (decodeError != null) ...[
            SizedBox(height: SimSpace.md),
            SimNotice(text: tr('sim.header_invalid'), error: true),
            SizedBox(height: SimSpace.sm),
            SelectableText('$decodeError', style: context.textTheme.bodySmall),
          ],
          SizedBox(height: SimSpace.lg),
          Text(tr('sim.raw_hex'), style: context.textTheme.titleSmall),
          SizedBox(height: SimSpace.sm),
          Container(
            padding: EdgeInsets.all(SimSpace.ms),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: AppBorders.input,
            ),
            child: SelectableText(
              key: const ValueKey('log-detail-hex'),
              log.hex.isEmpty ? tr('sim.no_packet') : _formatHex(log.hex),
              style: simCodeStyle(context),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatHex(String raw) {
  final hex = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (hex.length.isOdd || !RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return raw;
  final result = StringBuffer();
  for (var i = 0; i < hex.length; i += 2) {
    if (i > 0) result.write(i % 32 == 0 ? '\n' : ' ');
    result.write(hex.substring(i, i + 2));
  }
  return result.toString();
}

class _DetailValue extends StatelessWidget {
  const _DetailValue(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: SimSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(width: SimSpace.md),
        Expanded(child: SelectableText(value, style: simNumberStyle(context))),
      ],
    ),
  );
}
