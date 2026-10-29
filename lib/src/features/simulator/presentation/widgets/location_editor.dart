import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

class LocationEditor extends StatefulWidget {
  const LocationEditor({
    super.key,
    required this.controller,
    required this.terminalId,
  });
  final SimulatorController controller;
  final String terminalId;

  @override
  State<LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<LocationEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  bool _dirty = false;
  RequestState<void> _operation = const RequestInitial();
  LocationFix? _displayed;

  @override
  void initState() {
    super.initState();
    for (final key in [
      'latitude',
      'longitude',
      'speed',
      'altitude',
      'direction',
      'mileage',
      'alarm',
      'status',
    ]) {
      _fields[key] = TextEditingController();
    }
    _sync();
  }

  void _sync() {
    final fix = widget.controller.runtime(widget.terminalId).location;
    _displayed = fix;
    final values = {
      'latitude': fix.latitude.toStringAsFixed(6),
      'longitude': fix.longitude.toStringAsFixed(6),
      'speed': '${fix.speed}',
      'altitude': '${fix.altitude}',
      'direction': '${fix.direction}',
      'mileage': fix.mileage.toStringAsFixed(1),
      'alarm': simHex(fix.alarm),
      'status': simHex(fix.status),
    };
    for (final entry in values.entries) {
      _fields[entry.key]!.text = entry.value;
    }
  }

  @override
  void didUpdateWidget(covariant LocationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty &&
        widget.controller.runtime(widget.terminalId).location != _displayed) {
      _sync();
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  int? _bits(String key) {
    final text = _fields[key]!.text.trim();
    if (!RegExp(r'^(?:0[xX])?[0-9a-fA-F]{1,8}$').hasMatch(text)) return null;
    return int.tryParse(text.replaceFirst(RegExp(r'^0[xX]'), ''), radix: 16);
  }

  void _change() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _toggle(String key, int bit, bool enabled) {
    final value = _bits(key);
    if (value == null) return;
    setState(() {
      _fields[key]!.text = simHex(
        enabled ? value | (1 << bit) : value & ~(1 << bit),
      );
      _dirty = true;
    });
  }

  bool get _running => widget.controller.tasks.any(
    (task) =>
        task.terminalId == widget.terminalId &&
        widget.controller.taskRuntimes[task.id]?.phase == TaskPhase.running,
  );

  Future<void> _apply({bool send = false}) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _operation = const RequestLoading());
    try {
      final fix = _running
          ? widget.controller
                .runtime(widget.terminalId)
                .location
                .copyWith(alarm: _bits('alarm')!, status: _bits('status')!)
          : LocationFix(
              latitude: double.parse(_fields['latitude']!.text),
              longitude: double.parse(_fields['longitude']!.text),
              speed: double.parse(_fields['speed']!.text),
              altitude: int.parse(_fields['altitude']!.text),
              direction: int.parse(_fields['direction']!.text),
              mileage: double.parse(_fields['mileage']!.text),
              alarm: _bits('alarm')!,
              status: _bits('status')!,
            );
      widget.controller.updateLocation(widget.terminalId, fix);
      if (send) await widget.controller.sendLocation(widget.terminalId);
      if (mounted) {
        setState(() {
          _dirty = false;
          _operation = const RequestSuccess(null);
          _sync();
        });
        ShadToaster.of(context).show(
          ShadToast(
            description: Text(
              tr(send ? 'sim.location_sent' : 'sim.location_applied'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _operation = RequestFailure(
            UnknownFailure(simError(error), error: error),
          ),
        );
      }
    }
  }

  Widget _flag(String key, int bit, String label, bool blocked) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.all(SimSpace.ms),
        child: ShadCheckbox(
          enabled: !blocked && _bits(key) != null,
          value: ((_bits(key) ?? 0) & (1 << bit)) != 0,
          onChanged: blocked || _bits(key) == null
              ? null
              : (value) => _toggle(key, bit, value),
        ),
      ),
      Flexible(
        child: Text(tr('sim.$label'), style: context.textTheme.bodySmall),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final running = _running;
    final blocked = _operation.isLoading;
    final online = c.runtime(widget.terminalId).phase == ConnectionPhase.online;
    Widget field(String key, FormFieldValidator<String> validator) => SimField(
      key: ValueKey('location-$key'),
      label: tr('sim.field.$key'),
      controller: _fields[key]!,
      enabled: !blocked && !running,
      validator: validator,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: (_) => _change(),
    );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (running) ...[
            SimNotice(text: tr('sim.manual_during_task')),
            SizedBox(height: SimSpace.md),
          ],
          if (_operation case RequestFailure(:final failure)) ...[
            SimNotice(text: failure.message, error: true),
            SizedBox(height: SimSpace.md),
          ],
          SimFieldGrid(
            minWidth: 170,
            children: [
              field('latitude', (v) => simDoubleRange(v, -90, 90)),
              field('longitude', (v) => simDoubleRange(v, -180, 180)),
              field('speed', (v) => simDoubleRange(v, 0, 6553.5)),
              field('altitude', (v) => simIntRange(v, 0, 65535)),
              field('direction', (v) => simIntRange(v, 0, 359)),
              field('mileage', (v) => simDoubleRange(v, 0, 429496729.5)),
            ],
          ),
          SizedBox(height: SimSpace.lg),
          Text(tr('sim.status_bits'), style: context.textTheme.titleSmall),
          SizedBox(height: SimSpace.sm),
          Wrap(
            spacing: SimSpace.sm,
            runSpacing: SimSpace.xs,
            children: [
              _flag('status', 0, 'acc', blocked),
              _flag('status', 1, 'positioned', blocked),
            ],
          ),
          SizedBox(height: SimSpace.sm),
          Text(tr('sim.alarm_bits'), style: context.textTheme.titleSmall),
          Wrap(
            spacing: SimSpace.sm,
            runSpacing: SimSpace.xs,
            children: [
              for (final entry in {
                0: 'alarm_emergency',
                1: 'alarm_overspeed',
                2: 'alarm_fatigue',
                7: 'alarm_low_voltage',
                8: 'alarm_power_loss',
              }.entries)
                _flag('alarm', entry.key, entry.value, blocked),
            ],
          ),
          SizedBox(height: SimSpace.md),
          SimFieldGrid(
            minWidth: 220,
            children: [
              for (final key in ['alarm', 'status'])
                SimField(
                  key: ValueKey('location-$key'),
                  label: tr('sim.field.$key'),
                  controller: _fields[key]!,
                  enabled: !blocked,
                  helper: tr('sim.hex32_hint'),
                  validator: (_) => _bits(key) == null
                      ? tr('sim.errors.invalid_flags')
                      : null,
                  onChanged: (_) => setState(() => _dirty = true),
                ),
            ],
          ),
          SizedBox(height: SimSpace.md),
          Wrap(
            spacing: SimSpace.sm,
            runSpacing: SimSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SimButton(
                label: tr('sim.apply_location'),
                onPressed: blocked ? null : () => _apply(),
              ),
              SimButton(
                label: tr('sim.apply_send_location'),
                icon: Icons.near_me_outlined,
                primary: true,
                loading: _operation.isLoading,
                onPressed: !online || blocked ? null : () => _apply(send: true),
              ),
              if (_dirty)
                Text(
                  tr('sim.unsaved_location'),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
