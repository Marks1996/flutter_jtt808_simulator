import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

Future<void> showTerminalEditor(
  BuildContext context,
  SimulatorController controller, [
  TerminalConfig? terminal,
]) => showShadDialog<void>(
  context: context,
  builder: (_) => TerminalEditor(controller: controller, terminal: terminal),
);

class TerminalEditor extends StatefulWidget {
  const TerminalEditor({super.key, required this.controller, this.terminal});
  final SimulatorController controller;
  final TerminalConfig? terminal;

  @override
  State<TerminalEditor> createState() => _TerminalEditorState();
}

class _TerminalEditorState extends State<TerminalEditor> {
  final _form = GlobalKey<FormState>();
  late final TerminalConfig _initial;
  late final Map<String, TextEditingController> _fields;
  late final Map<String, String> _initialValues;
  late int _plateColor;
  late bool _autoReconnect;
  bool _showAuth = false;
  RequestState<void> _save = const RequestInitial();

  @override
  void initState() {
    super.initState();
    _initial = widget.terminal ?? TerminalConfig(id: widget.controller.newId());
    _fields = {
      for (final entry in _initial.toJson().entries)
        if (entry.value is String || entry.value is int)
          entry.key: TextEditingController(text: '${entry.value}'),
    };
    _initialValues = {
      for (final entry in _fields.entries) entry.key: entry.value.text,
    };
    _plateColor = _initial.plateColor;
    _autoReconnect = _initial.autoReconnect;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _hasChanges =>
      _fields.entries.any(
        (entry) => entry.value.text != _initialValues[entry.key],
      ) ||
      _plateColor != _initial.plateColor ||
      _autoReconnect != _initial.autoReconnect;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _save = const RequestLoading());
    try {
      final config = TerminalConfig(
        id: _initial.id,
        name: _fields['name']!.text.trim(),
        host: _fields['host']!.text.trim(),
        port: int.parse(_fields['port']!.text),
        phone: _fields['phone']!.text.trim(),
        province: int.parse(_fields['province']!.text),
        city: int.parse(_fields['city']!.text),
        manufacturer: _fields['manufacturer']!.text.trim(),
        model: _fields['model']!.text.trim(),
        terminalId: _fields['terminalId']!.text.trim(),
        plate: _fields['plate']!.text.trim(),
        plateColor: _plateColor,
        authCode: _fields['authCode']!.text,
        heartbeatSeconds: int.parse(_fields['heartbeatSeconds']!.text),
        locationIntervalSeconds: int.parse(
          _fields['locationIntervalSeconds']!.text,
        ),
        autoReconnect: _autoReconnect,
      );
      await widget.controller.saveTerminal(config);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _save = RequestFailure(
            UnknownFailure(simError(error), error: error),
          ),
        );
      }
    }
  }

  Widget _field(
    String key, {
    FormFieldValidator<String>? validator,
    bool numeric = false,
    String? helper,
  }) => SimField(
    key: ValueKey('terminal-$key'),
    label: tr('sim.field.$key'),
    controller: _fields[key]!,
    validator: validator ?? simRequired,
    keyboardType: numeric ? TextInputType.number : null,
    helper: helper,
    enabled: !_save.isLoading,
  );

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(tr('sim.$title'), style: context.textTheme.titleSmall),
      SizedBox(height: SimSpace.md),
      SimFieldGrid(children: children),
      SizedBox(height: SimSpace.lg),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.runtime(_initial.id).busy;
      return SimEditGuard(
        hasChanges: () => _hasChanges,
        isSaving: () => _save.isLoading,
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          titlePinned: true,
          descriptionPinned: true,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          closeIcon: ShadIconButton.ghost(
            key: const ValueKey('dialog-close'),
            icon: Icon(LucideIcons.x, size: 16, semanticLabel: tr('sim.close')),
            width: 20,
            height: 20,
            padding: EdgeInsets.zero,
            foregroundColor: ShadTheme.of(
              context,
            ).colorScheme.foreground.withValues(alpha: .5),
            hoverBackgroundColor: Colors.transparent,
            hoverForegroundColor: ShadTheme.of(context).colorScheme.foreground,
            pressedForegroundColor: ShadTheme.of(
              context,
            ).colorScheme.foreground,
            enabled: !_save.isLoading,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            tr(
              widget.terminal == null
                  ? 'sim.create_terminal'
                  : 'sim.edit_terminal',
            ),
          ),
          description: Text(tr('sim.dialog.terminal_description')),
          actions: [
            ShadButton.outline(
              enabled: !_save.isLoading,
              onPressed: _save.isLoading
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: Text(tr('sim.cancel')),
            ),
            ShadButton(
              key: const ValueKey('save-terminal'),
              enabled: !_save.isLoading && !busy,
              onPressed: _save.isLoading || busy ? null : _submit,
              child: Text(tr(_save.isLoading ? 'sim.saving' : 'sim.save')),
            ),
          ],
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy) ...[
                  SimNotice(
                    text: tr('sim.errors.disconnect_before_edit'),
                    error: true,
                  ),
                  SizedBox(height: SimSpace.md),
                ],
                if (_save case RequestFailure(:final failure)) ...[
                  SimNotice(text: failure.message, error: true),
                  SizedBox(height: SimSpace.md),
                ],
                AbsorbPointer(
                  absorbing: busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('terminal_connection', [
                        _field('name'),
                        _field(
                          'phone',
                          validator: (v) =>
                              RegExp(r'^\d{12}$').hasMatch(v ?? '')
                              ? null
                              : tr('sim.errors.invalid_phone'),
                        ),
                        _field('host'),
                        _field(
                          'port',
                          numeric: true,
                          validator: (v) => simIntRange(v, 1, 65535),
                        ),
                      ]),
                      _section('terminal_registration', [
                        _field(
                          'province',
                          numeric: true,
                          validator: (v) => simIntRange(v, 0, 65535),
                        ),
                        _field(
                          'city',
                          numeric: true,
                          validator: (v) => simIntRange(v, 0, 65535),
                        ),
                        _field(
                          'manufacturer',
                          validator: (v) =>
                              RegExp(r'^[A-Z0-9]{1,5}$').hasMatch(v ?? '')
                              ? null
                              : tr('sim.identity_manufacturer_hint'),
                        ),
                        _field(
                          'model',
                          validator: (v) =>
                              RegExp(r'^[\x20-\x7E]{1,20}$').hasMatch(v ?? '')
                              ? null
                              : tr('sim.identity_model_hint'),
                        ),
                        _field(
                          'terminalId',
                          validator: (v) =>
                              RegExp(r'^[A-Z0-9]{1,7}$').hasMatch(v ?? '')
                              ? null
                              : tr('sim.identity_terminal_hint'),
                        ),
                        _field('plate'),
                        SimSelect<int>(
                          label: tr('sim.field.plateColor'),
                          value: _plateColor,
                          items: [
                            for (final color in [0, 1, 2, 3, 4, 9])
                              SimOption(
                                value: color,
                                child: Text(tr('sim.plate_color.$color')),
                              ),
                          ],
                          onChanged: _save.isLoading
                              ? null
                              : (value) => setState(() => _plateColor = value!),
                        ),
                      ]),
                      Text(
                        tr('sim.terminal_auth'),
                        style: context.textTheme.titleSmall,
                      ),
                      SizedBox(height: SimSpace.md),
                      SimField(
                        key: const ValueKey('terminal-authCode'),
                        label: tr('sim.field.authCode'),
                        controller: _fields['authCode']!,
                        obscure: !_showAuth,
                        enabled: !_save.isLoading,
                        helper: tr('sim.auth_hint'),
                        suffix: SimIconButton(
                          tooltip: tr(
                            _showAuth ? 'sim.hide_auth' : 'sim.show_auth',
                          ),
                          onPressed: () =>
                              setState(() => _showAuth = !_showAuth),
                          icon: Icon(
                            _showAuth
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                      SizedBox(height: SimSpace.lg),
                      _section('terminal_intervals', [
                        _field(
                          'heartbeatSeconds',
                          numeric: true,
                          validator: (v) => simIntRange(v, 1, 3600),
                        ),
                        _field(
                          'locationIntervalSeconds',
                          numeric: true,
                          validator: (v) => simIntRange(v, 1, 3600),
                        ),
                      ]),
                      ShadSwitch(
                        value: _autoReconnect,
                        enabled: !_save.isLoading,
                        label: Text(
                          tr('sim.field.autoReconnect'),
                          style: context.textTheme.bodyMedium,
                        ),
                        sublabel: Text(
                          tr('sim.auto_reconnect_hint'),
                          style: context.textTheme.bodySmall,
                        ),
                        onChanged: (value) =>
                            setState(() => _autoReconnect = value),
                      ),
                      SizedBox(height: SimSpace.md),
                      SimKeyValue(tr('sim.workspace_id'), _initial.id),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
