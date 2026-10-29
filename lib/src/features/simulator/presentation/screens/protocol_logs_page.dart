import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import '../widgets/log_detail_dialog.dart';
import '../widgets/sim_ui.dart';

class ProtocolLogsPage extends StatefulWidget {
  const ProtocolLogsPage({
    super.key,
    required this.controller,
    required this.terminalId,
    required this.onTerminalChanged,
  });
  final SimulatorController controller;
  final String? terminalId;
  final ValueChanged<String?> onTerminalChanged;

  @override
  State<ProtocolLogsPage> createState() => _ProtocolLogsPageState();
}

class _ProtocolLogsPageState extends State<ProtocolLogsPage> {
  final _search = TextEditingController();
  String? _filterTerminal;
  LogDirection? _direction;
  List<ProtocolLog>? _frozen;

  @override
  void initState() {
    super.initState();
    _filterTerminal = widget.terminalId;
  }

  @override
  void didUpdateWidget(covariant ProtocolLogsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminalId != widget.terminalId) {
      _filterTerminal = widget.terminalId;
    }
  }

  void _changeTerminal(String? value) {
    final id = value == '' ? null : value;
    setState(() => _filterTerminal = id);
    if (id != null) widget.onTerminalChanged(id);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final source = _frozen ?? c.logs;
    final query = _search.text.replaceAll(RegExp(r'\s'), '').toLowerCase();
    final selectedTerminal = c.terminals.any((t) => t.id == _filterTerminal)
        ? _filterTerminal
        : null;
    final logs = source
        .where(
          (log) =>
              (selectedTerminal == null ||
                  selectedTerminal == log.terminalId) &&
              (_direction == null || _direction == log.direction) &&
              (query.isEmpty ||
                  log.idHex.toLowerCase().contains(query) ||
                  log.hex
                      .replaceAll(RegExp(r'\s'), '')
                      .toLowerCase()
                      .contains(query) ||
                  log.message.toLowerCase().contains(query)),
        )
        .toList()
        .reversed
        .toList();
    return LayoutBuilder(
      builder: (context, available) => SimPage(
        title: tr('sim.protocol_logs'),
        subtitle: '',
        actions: [
          SimButton(
            label: tr(
              _frozen == null ? 'sim.pause_display' : 'sim.resume_display',
            ),
            icon: _frozen == null ? Icons.pause : Icons.play_arrow,
            onPressed: () =>
                setState(() => _frozen = _frozen == null ? c.logs : null),
          ),
          SimButton(
            label: tr('sim.clear_logs'),
            icon: Icons.delete_outline,
            onPressed: c.logs.isEmpty && source.isEmpty
                ? null
                : () async {
                    if (await simConfirm(
                      context,
                      title: tr('sim.clear_logs'),
                      body: tr('sim.clear_logs_confirm'),
                      confirm: tr('sim.clear'),
                      destructive: true,
                    )) {
                      c.clearLogs();
                      if (mounted) {
                        setState(() {
                          if (_frozen != null) _frozen = [];
                        });
                      }
                    }
                  },
          ),
          ShadTooltip(
            builder: (_) => Text(tr('sim.export_logs_hint')),
            child: SimButton(
              label: tr('sim.copy_logs_json'),
              icon: Icons.copy_outlined,
              onPressed: () =>
                  simCopy(context, c.exportLogs(terminalId: selectedTerminal)),
            ),
          ),
        ],
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final phone = constraints.maxWidth < 480;
              final filterWidth = constraints.maxWidth - SimSpace.ms;
              return Wrap(
                spacing: SimSpace.ms,
                runSpacing: SimSpace.ms,
                children: [
                  SizedBox(
                    width: phone ? constraints.maxWidth : 240,
                    child: SimField(
                      label: tr('sim.search_logs'),
                      compact: true,
                      controller: _search,
                      hint: tr('sim.search_logs_hint'),
                      onChanged: (_) => setState(() {}),
                      suffix: _search.text.isEmpty
                          ? Icon(
                              Icons.search,
                              size: 16,
                              color: context.colors.onSurfaceVariant,
                            )
                          : SimIconButton(
                              tooltip: tr('sim.clear_search'),
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: phone ? math.min(200, filterWidth * .56) : 200,
                    child: SimSelect<String>(
                      key: const ValueKey('log-terminal-filter'),
                      label: tr('sim.terminal_filter'),
                      compact: true,
                      value: selectedTerminal ?? '',
                      items: [
                        SimOption(
                          value: '',
                          child: Text(tr('sim.all_terminals')),
                        ),
                        ...c.terminals.map(
                          (t) => SimOption(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _changeTerminal,
                    ),
                  ),
                  SizedBox(
                    width: phone ? math.min(160, filterWidth * .44) : 160,
                    child: SimSelect<String>(
                      label: tr('sim.direction_filter'),
                      compact: true,
                      value: _direction?.name ?? '',
                      items: [
                        SimOption(
                          value: '',
                          child: Text(tr('sim.all_directions')),
                        ),
                        ...LogDirection.values.map(
                          (d) => SimOption(
                            value: d.name,
                            child: Text(tr('sim.log_direction.${d.name}')),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _direction = value == ''
                            ? null
                            : LogDirection.values.byName(value!),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_frozen != null)
            Text(
              tr(
                'sim.display_paused_hint',
                namedArgs: {'count': '${c.logs.length}'},
              ),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          _ProtocolLogTable(
            controller: c,
            logs: logs,
            sourceCount: source.length,
            maxHeight: math.max(
              80,
              available.maxHeight - (available.maxWidth < 720 ? 300 : 220),
            ),
          ),
          _RawSender(
            controller: c,
            terminalId:
                selectedTerminal ??
                (c.terminals.any((terminal) => terminal.id == widget.terminalId)
                    ? widget.terminalId
                    : null),
            onTerminalChanged: _changeTerminal,
          ),
        ],
      ),
    );
  }
}

class _ProtocolLogTable extends StatelessWidget {
  const _ProtocolLogTable({
    required this.controller,
    required this.logs,
    required this.sourceCount,
    required this.maxHeight,
  });

  final SimulatorController controller;
  final List<ProtocolLog> logs;
  final int sourceCount;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 800;
      final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.4;
      final rowHeight = math.max(
        wide ? 52.0 : 76.0,
        lineHeight * (wide ? 2 : 3) + SimSpace.lg,
      );
      final headingStyle = context.textTheme.bodySmall?.copyWith(
        color: context.colors.onSurfaceVariant,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                tr(
                  'sim.log_count',
                  namedArgs: {
                    'visible': '${logs.length}',
                    'total': '$sourceCount',
                  },
                ),
                style: headingStyle,
              ),
              SizedBox(width: SimSpace.ms),
              ShadTooltip(
                builder: (_) => Text(
                  tr(
                    'sim.logs_subtitle',
                    namedArgs: {'limit': '${SimulatorController.logLimit}'},
                  ),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: context.colors.onSurfaceVariant,
                  semanticLabel: tr(
                    'sim.logs_subtitle',
                    namedArgs: {'limit': '${SimulatorController.logLimit}'},
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: SimSpace.ms),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: SimSpace.ms,
              vertical: SimSpace.ms,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: headingStyle,
              child: wide
                  ? _LogColumns(
                      time: Text(tr('sim.time')),
                      terminal: Text(tr('sim.terminal')),
                      direction: Text(tr('sim.direction')),
                      messageId: Text(tr('sim.message_id')),
                      details: Text(tr('sim.log_detail')),
                    )
                  : Row(
                      children: [
                        Expanded(child: Text(tr('sim.log_detail'))),
                        Text(tr('sim.time')),
                      ],
                    ),
            ),
          ),
          if (logs.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: SimSpace.ms,
                vertical: SimSpace.md,
              ),
              child: Text(
                tr(
                  sourceCount == 0
                      ? 'sim.no_logs_hint'
                      : 'sim.no_matching_logs',
                ),
                style: headingStyle,
              ),
            )
          else
            SizedBox(
              height: math.min(logs.length * rowHeight, maxHeight),
              child: ListView.builder(
                key: const ValueKey('protocol-log-list'),
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: logs.length,
                itemExtent: rowHeight,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final terminal = controller.terminals
                      .where((t) => t.id == log.terminalId)
                      .firstOrNull;
                  return _ProtocolLogRow(
                    controller: controller,
                    log: log,
                    terminalName: terminal?.name ?? log.terminalId,
                    wide: wide,
                    height: rowHeight,
                  );
                },
              ),
            ),
        ],
      );
    },
  );
}

class _LogColumns extends StatelessWidget {
  const _LogColumns({
    required this.time,
    required this.terminal,
    required this.direction,
    required this.messageId,
    required this.details,
  });

  final Widget time, terminal, direction, messageId, details;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 104,
        child: Align(alignment: Alignment.centerRight, child: time),
      ),
      SizedBox(width: SimSpace.lg),
      SizedBox(width: 144, child: terminal),
      SizedBox(width: SimSpace.lg),
      SizedBox(width: 84, child: direction),
      SizedBox(width: SimSpace.lg),
      SizedBox(
        width: 80,
        child: Align(alignment: Alignment.centerRight, child: messageId),
      ),
      SizedBox(width: SimSpace.lg),
      Expanded(child: details),
      SizedBox(width: SimSpace.ms + 16),
    ],
  );
}

class _ProtocolLogRow extends StatelessWidget {
  const _ProtocolLogRow({
    required this.controller,
    required this.log,
    required this.terminalName,
    required this.wide,
    required this.height,
  });

  final SimulatorController controller;
  final ProtocolLog log;
  final String terminalName;
  final bool wide;
  final double height;

  @override
  Widget build(BuildContext context) {
    final secondary = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final numeric = simNumberStyle(context)?.copyWith(fontSize: 13);
    final icon = log.isError
        ? Icons.error_outline
        : switch (log.direction) {
            LogDirection.sent => Icons.north_east,
            LogDirection.received => Icons.south_west,
            LogDirection.event => Icons.info_outline,
          };
    final direction = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: log.isError
              ? context.colors.error
              : context.colors.onSurfaceVariant,
        ),
        SizedBox(width: SimSpace.sm),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            tr('sim.log_direction.${log.direction.name}'),
            style: secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final message = Text(
      log.message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodyMedium?.copyWith(fontSize: 13),
    );
    final hex = Text(
      log.hex,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: secondary?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return ShadButton.ghost(
      height: height,
      expands: true,
      padding: EdgeInsets.zero,
      onPressed: () => showLogDetail(context, controller, log),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: SimSpace.ms),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: context.colors.outlineVariant.withValues(alpha: .55),
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            if (wide)
              _LogColumns(
                time: Text(simTime(log.time), style: numeric),
                terminal: Text(
                  terminalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
                direction: direction,
                messageId: Text(log.idHex, style: numeric),
                details: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [message, if (log.hex.isNotEmpty) hex],
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(right: SimSpace.ms + 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            terminalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        ),
                        SizedBox(width: SimSpace.ms),
                        Text(simTime(log.time), style: numeric),
                      ],
                    ),
                    Row(
                      children: [
                        direction,
                        SizedBox(width: SimSpace.ms),
                        Text(log.idHex, style: numeric),
                        SizedBox(width: SimSpace.ms),
                        Expanded(child: message),
                      ],
                    ),
                    if (log.hex.isNotEmpty) hex,
                  ],
                ),
              ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RawSender extends StatefulWidget {
  const _RawSender({
    required this.controller,
    required this.terminalId,
    required this.onTerminalChanged,
  });
  final SimulatorController controller;
  final String? terminalId;
  final ValueChanged<String?> onTerminalChanged;

  @override
  State<_RawSender> createState() => _RawSenderState();
}

class _RawSenderState extends State<_RawSender> {
  final _hex = TextEditingController();
  final _form = GlobalKey<FormState>();
  RequestState<void> _send = const RequestInitial();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || widget.terminalId == null) return;
    setState(() => _send = const RequestLoading());
    try {
      await widget.controller.sendRaw(widget.terminalId!, _hex.text);
      if (mounted) setState(() => _send = const RequestSuccess(null));
    } catch (error) {
      if (mounted) {
        setState(
          () => _send = RequestFailure(
            UnknownFailure(tr('sim.raw_send_failed'), error: error),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SimExpansion(
    key: const PageStorageKey('raw-sender'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.only(bottom: SimSpace.sm),
    title: Text(tr('sim.raw_send'), style: context.textTheme.titleSmall),
    children: [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('sim.raw_send_hint'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: SimSpace.md),
            if (_send case RequestFailure(:final failure)) ...[
              SimNotice(text: failure.message, error: true),
              if (failure.error != null)
                SelectableText(
                  '${failure.error}',
                  style: context.textTheme.bodySmall,
                ),
              SizedBox(height: SimSpace.ms),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final terminal = SizedBox(
                  width: math.min(200, constraints.maxWidth),
                  child: SimSelect<String>(
                    key: const ValueKey('raw-send-terminal'),
                    label: tr('sim.send_terminal'),
                    value: widget.terminalId,
                    items: widget.controller.terminals
                        .map(
                          (t) => SimOption(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: widget.onTerminalChanged,
                  ),
                );
                final frame = SimField(
                  label: tr('sim.raw_hex'),
                  controller: _hex,
                  hint: tr('sim.raw_hex_hint'),
                  validator: (value) {
                    final text = (value ?? '').replaceAll(RegExp(r'\s'), '');
                    return text.isEmpty ||
                            text.length.isOdd ||
                            !RegExp(r'^[0-9a-fA-F]+$').hasMatch(text) ||
                            text.length > 4148
                        ? tr('sim.errors.invalid_hex')
                        : null;
                  },
                );
                final send = SimButton(
                  label: tr('sim.send_raw'),
                  primary: true,
                  loading: _send.isLoading,
                  onPressed:
                      widget.terminalId != null &&
                          widget.controller.runtime(widget.terminalId!).phase ==
                              ConnectionPhase.online
                      ? _submit
                      : null,
                );
                if (constraints.maxWidth >= 800) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      terminal,
                      SizedBox(width: SimSpace.md),
                      Expanded(child: frame),
                      SizedBox(width: SimSpace.md),
                      send,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    terminal,
                    SizedBox(height: SimSpace.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: frame,
                    ),
                    SizedBox(height: SimSpace.md),
                    send,
                  ],
                );
              },
            ),
            if (_send.isSuccess)
              Padding(
                padding: EdgeInsets.only(top: SimSpace.ms),
                child: Text(
                  tr('sim.raw_sent'),
                  style: context.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
