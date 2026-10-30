import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

class RoutingSettingsForm extends StatefulWidget {
  const RoutingSettingsForm({super.key, required this.controller});
  final SimulatorController controller;
  @override
  State<RoutingSettingsForm> createState() => _RoutingSettingsFormState();
}

class _RoutingSettingsFormState extends State<RoutingSettingsForm> {
  final _form = GlobalKey<FormState>();
  late RoutePlanningSettings _saved = widget.controller.workspace.routing;
  late RoutingProvider _provider = _saved.provider;
  late final _url = TextEditingController(text: _saved.osrmUrl);
  late final _key = TextEditingController(text: _saved.amapKey);
  late bool _authorized = _saved.amapAuthorized;
  RequestState<void> _save = const RequestInitial();

  RoutePlanningSettings get _value => RoutePlanningSettings(
    provider: _provider,
    osrmUrl: _url.text.trim(),
    amapKey: _key.text.trim(),
    amapAuthorized: _authorized,
  );

  @override
  void didUpdateWidget(covariant RoutingSettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.controller.workspace.routing;
    if (value != _saved) {
      _saved = value;
      _provider = value.provider;
      _authorized = value.amapAuthorized;
      _url.text = value.osrmUrl;
      _key.text = value.amapKey;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final value = _value;
    setState(() => _save = const RequestLoading());
    try {
      await widget.controller.setRouting(value);
      if (!mounted) return;
      setState(() {
        _saved = value;
        _save = widget.controller.saveState;
      });
      if (_save.isSuccess) {
        ShadToaster.of(
          context,
        ).show(ShadToast(description: Text(tr('sim.routing.saved'))));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _save = RequestFailure(UnknownFailure(simError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: SimPanel(
      title: tr('sim.routing.settings'),
      trailing: ShadButton(
        key: const ValueKey('save-routing'),
        size: ShadButtonSize.sm,
        enabled: !_save.isLoading && (_value != _saved || _save.isFailure),
        onPressed: _submit,
        child: Text(tr(_save.isLoading ? 'sim.saving' : 'sim.routing.save')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                ShadSelectFormField<RoutingProvider>(
                  key: ValueKey(('routing-provider', _provider)),
                  initialValue: _provider,
                  enabled: !_save.isLoading,
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                  label: Text(tr('sim.routing.source')),
                  options: [
                    for (final provider in RoutingProvider.values)
                      ShadOption(
                        value: provider,
                        child: Text(
                          tr('sim.routing.provider.${provider.name}'),
                        ),
                      ),
                  ],
                  selectedOptionBuilder: (_, value) =>
                      Text(tr('sim.routing.provider.${value.name}')),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _provider = value;
                        _save = const RequestInitial();
                      });
                    }
                  },
                ),
          ),
          SizedBox(height: SimSpace.md),
          Wrap(
            spacing: SimSpace.ms,
            runSpacing: SimSpace.ms,
            children: [
              ShadButton.outline(
                key: const ValueKey('use-public-osrm'),
                size: ShadButtonSize.sm,
                enabled: !_save.isLoading,
                onPressed: () => setState(() {
                  _provider = RoutingProvider.osrm;
                  _url.text = RoutePlanningSettings.publicDemoUrl;
                  _save = const RequestInitial();
                }),
                child: Text(tr('sim.keyless.osrm_preset')),
              ),
              ShadButton.outline(
                key: const ValueKey('use-fossgis-osrm'),
                size: ShadButtonSize.sm,
                enabled: !_save.isLoading,
                onPressed: () => setState(() {
                  _provider = RoutingProvider.osrm;
                  _url.text = RoutePlanningSettings.fossgisDemoUrl;
                  _save = const RequestInitial();
                }),
                child: Text(tr('sim.keyless.fossgis_preset')),
              ),
            ],
          ),
          ShadButton.link(
            height: 0,
            expands: true,
            padding: EdgeInsets.zero,
            mainAxisAlignment: MainAxisAlignment.start,
            onPressed: () => simRun(context, () async {
              if (!await launchUrl(
                Uri.parse(
                  'https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/',
                ),
                mode: LaunchMode.externalApplication,
              )) {
                throw StateError('Unable to open public routing policy');
              }
            }),
            child: Text(
              tr('sim.keyless.routing_policy'),
              style: context.textTheme.bodySmall,
            ),
          ),
          SizedBox(height: SimSpace.md),
          if (_provider == RoutingProvider.osrm) ...[
            ShadInputFormField(
              key: const PageStorageKey('routing-osrm-url'),
              controller: _url,
              enabled: !_save.isLoading,
              label: Text(tr('sim.routing.osrm_url')),
              description: Text(tr('sim.routing.osrm_url_help')),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final key = value.trim().isEmpty
                    ? null
                    : RoutePlanningSettings.validateOsrmUrl(value.trim());
                return key == null ? null : tr('sim.errors.$key');
              },
            ),
            if (RoutePlanningSettings.isPublicOsrmUrl(_url.text.trim())) ...[
              SizedBox(height: SimSpace.ms),
              Text(
                tr('sim.routing.demo_warning'),
                style: context.textTheme.bodySmall,
              ),
            ],
          ] else ...[
            ShadInputFormField(
              key: const PageStorageKey('routing-amap-key'),
              controller: _key,
              enabled: !_save.isLoading,
              label: Text(tr('sim.routing.amap_key')),
              description: Text(tr('sim.routing.amap_key_help')),
              obscureText: true,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (value) => RegExp(r'\s').hasMatch(value.trim())
                  ? tr('sim.errors.routing_key')
                  : null,
            ),
            SizedBox(height: SimSpace.ms),
            ShadButton.link(
              height: 0,
              expands: true,
              padding: EdgeInsets.zero,
              mainAxisAlignment: MainAxisAlignment.start,
              onPressed: () => simRun(context, () async {
                if (!await launchUrl(
                  Uri.parse(
                    'https://lbs.amap.com/api/webservice/create-project-and-key',
                  ),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw StateError('Unable to open Amap Key guide');
                }
              }),
              child: Text(tr('sim.routing.apply_key')),
            ),
            Text(
              tr('sim.routing.amap_warning'),
              style: context.textTheme.bodySmall,
            ),
            SizedBox(height: SimSpace.md),
            ShadCheckbox(
              key: const ValueKey('routing-amap-authorized'),
              value: _authorized,
              enabled: !_save.isLoading,
              onChanged: (value) => setState(() => _authorized = value),
              label: Text(tr('sim.routing.amap_authorized')),
            ),
          ],
          SizedBox(height: SimSpace.md),
          Text(
            tr('sim.routing.privacy'),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_save case RequestFailure()) ...[
            SizedBox(height: SimSpace.md),
            SimNotice(text: tr('sim.save_failure'), error: true),
          ],
        ],
      ),
    ),
  );
}
