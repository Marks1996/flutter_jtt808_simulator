import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

import '../providers/simulator_provider.dart';
import 'sim_ui.dart';

class BasemapSettingsForm extends StatefulWidget {
  const BasemapSettingsForm({super.key, required this.controller});

  final SimulatorController controller;

  @override
  State<BasemapSettingsForm> createState() => _BasemapSettingsFormState();
}

class _BasemapSettingsFormState extends State<BasemapSettingsForm> {
  final _form = GlobalKey<FormState>();
  late BasemapSettings _saved = widget.controller.workspace.basemap;
  late BasemapSettings _draft = _saved;
  late final _tiandituKey = TextEditingController(text: _draft.tiandituKey);
  late final _amapKey = TextEditingController(text: _draft.amapKey);
  late final _baiduKey = TextEditingController(text: _draft.baiduKey);
  late final _url = TextEditingController(text: _draft.tileTemplate);
  late final _attribution = TextEditingController(
    text: _draft.customAttribution,
  );
  RequestState<void> _save = const RequestInitial();

  BasemapSettings get _value => _draft.copyWith(
    tiandituKey: _tiandituKey.text.trim(),
    amapKey: _amapKey.text.trim(),
    baiduKey: _baiduKey.text.trim(),
    osmUrl: _draft.provider == BasemapProvider.openStreetMap
        ? _url.text.trim()
        : null,
    amapUrl: _draft.provider == BasemapProvider.amap ? _url.text.trim() : null,
    baiduUrl: _draft.provider == BasemapProvider.baidu
        ? _url.text.trim()
        : null,
    customUrl: _draft.provider == BasemapProvider.custom
        ? _url.text.trim()
        : null,
    customAttribution: _attribution.text.trim(),
  );

  @override
  void didUpdateWidget(covariant BasemapSettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.controller.workspace.basemap;
    if (current != _saved) {
      _saved = _draft = current;
      _url.text = current.tileTemplate;
      _amapKey.text = current.amapKey;
      _baiduKey.text = current.baiduKey;
      _tiandituKey.text = current.tiandituKey;
      _attribution.text = current.customAttribution;
    }
  }

  @override
  void dispose() {
    _tiandituKey.dispose();
    _amapKey.dispose();
    _baiduKey.dispose();
    _url.dispose();
    _attribution.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final value = _value;
    setState(() => _save = const RequestLoading());
    try {
      await widget.controller.setBasemap(value);
      if (!mounted) return;
      setState(() {
        _saved = _draft = value;
        _save = widget.controller.saveState;
      });
      if (_save.isSuccess) {
        ShadToaster.of(
          context,
        ).show(ShadToast(description: Text(tr('sim.basemap_saved'))));
      }
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

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: SimPanel(
      title: tr('sim.basemap_settings'),
      trailing: ShadButton(
        key: const ValueKey('save-basemap'),
        size: ShadButtonSize.sm,
        enabled: !_save.isLoading && (_value != _saved || _save.isFailure),
        onPressed: _submit,
        child: Text(tr(_save.isLoading ? 'sim.saving' : 'sim.save_basemap')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadSwitch(
            key: const ValueKey('basemap-default-enabled'),
            value: _draft.enabled,
            enabled: !_save.isLoading,
            label: Text(tr('sim.basemap_default_enabled')),
            onChanged: (value) => setState(() {
              _draft = _draft.copyWith(enabled: value);
            }),
          ),
          SizedBox(height: SimSpace.md),
          LayoutBuilder(
            builder: (context, constraints) =>
                ShadSelectFormField<BasemapProvider>(
                  key: ValueKey(('basemap-provider', _draft.provider)),
                  initialValue: _draft.provider,
                  enabled: !_save.isLoading,
                  label: Text(tr('sim.basemap_source')),
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                  options: [
                    for (final provider in BasemapProvider.values)
                      ShadOption(
                        value: provider,
                        child: Text(
                          tr('sim.basemap_provider.${provider.name}'),
                        ),
                      ),
                  ],
                  selectedOptionBuilder: (context, value) =>
                      Text(tr('sim.basemap_provider.${value.name}')),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _draft = _value.copyWith(provider: value);
                      _url.text = _draft.tileTemplate;
                      _save = const RequestInitial();
                    });
                  },
                ),
          ),
          SizedBox(height: SimSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              key: const ValueKey('use-public-imagery'),
              size: ShadButtonSize.sm,
              enabled: !_save.isLoading,
              onPressed: () => setState(() {
                _draft = _value.copyWith(
                  provider: BasemapProvider.custom,
                  customCoordinates: BasemapCoordinates.wgs84,
                );
                _url.text = BasemapSettings.publicImageryUrl;
                _attribution.text = BasemapSettings.publicImageryAttribution;
                _save = const RequestInitial();
              }),
              child: Text(tr('sim.keyless.imagery_preset')),
            ),
          ),
          SizedBox(height: SimSpace.ms),
          Text(
            tr('sim.keyless.imagery_help'),
            style: context.textTheme.bodySmall,
          ),
          ShadButton.link(
            height: 0,
            expands: true,
            padding: EdgeInsets.zero,
            mainAxisAlignment: MainAxisAlignment.start,
            onPressed: () => simRun(context, () async {
              if (!await launchUrl(
                Uri.parse(BasemapSettings.publicImageryInfoUrl),
                mode: LaunchMode.externalApplication,
              )) {
                throw StateError('Unable to open imagery service information');
              }
            }),
            child: Text(
              tr('sim.keyless.imagery_terms'),
              style: context.textTheme.bodySmall,
            ),
          ),
          if (_draft.provider == BasemapProvider.tianditu) ...[
            SizedBox(height: SimSpace.md),
            ShadInputFormField(
              key: const PageStorageKey('basemap-tianditu-key'),
              controller: _tiandituKey,
              enabled: !_save.isLoading,
              label: Text(tr('sim.tianditu_key')),
              description: Text(tr('sim.tianditu_key_help')),
              obscureText: true,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final key = BasemapSettings.validateTiandituKey(value.trim());
                return key == null ? null : tr('sim.errors.$key');
              },
            ),
            ShadButton.link(
              height: 0,
              expands: true,
              padding: EdgeInsets.zero,
              mainAxisAlignment: MainAxisAlignment.start,
              onPressed: () => simRun(context, () async {
                if (!await launchUrl(
                  Uri.parse('https://console.tianditu.gov.cn/api/key'),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw StateError('Unable to open Tianditu console');
                }
              }),
              child: Text(tr('sim.tianditu_apply_key')),
            ),
          ],
          if (_draft.supportsKeyPlaceholder) ...[
            SizedBox(height: SimSpace.md),
            ShadInputFormField(
              key: PageStorageKey(
                _draft.provider == BasemapProvider.amap
                    ? 'basemap-amap-key'
                    : 'basemap-baidu-key',
              ),
              controller: _draft.provider == BasemapProvider.amap
                  ? _amapKey
                  : _baiduKey,
              enabled: !_save.isLoading,
              label: Text(
                tr(
                  _draft.provider == BasemapProvider.amap
                      ? 'sim.amap_tile_key'
                      : 'sim.baidu_tile_key',
                ),
              ),
              description: Text(tr('sim.vendor_tile_key_help')),
              obscureText: true,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final key = BasemapSettings.validateProviderKey(value.trim());
                return key == null ? null : tr('sim.errors.$key');
              },
            ),
          ],
          if (_draft.provider != BasemapProvider.tianditu) ...[
            SizedBox(height: SimSpace.md),
            ShadInputFormField(
              key: const PageStorageKey('basemap-tile-url'),
              controller: _url,
              enabled: !_save.isLoading,
              label: Text(
                tr(
                  _draft.supportsKeyPlaceholder
                      ? 'sim.basemap_authorized_url'
                      : 'sim.basemap_url',
                ),
              ),
              description: Text(
                tr(
                  _draft.provider == BasemapProvider.openStreetMap
                      ? 'sim.osm_connection_help'
                      : _draft.provider == BasemapProvider.baidu
                      ? 'sim.basemap_baidu_url_hint'
                      : 'sim.basemap_url_hint',
                ),
              ),
              placeholder: const Text(
                'https://tiles.example.com/{z}/{x}/{y}.png',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final key = value.trim().isEmpty
                    ? null
                    : BasemapSettings.validateUrl(
                        value.trim(),
                        allowKey: _draft.supportsKeyPlaceholder,
                      );
                return key == null ? null : tr('sim.errors.$key');
              },
            ),
          ],
          if (_draft.provider == BasemapProvider.custom) ...[
            SizedBox(height: SimSpace.md),
            LayoutBuilder(
              builder: (context, constraints) =>
                  ShadSelectFormField<BasemapCoordinates>(
                    key: ValueKey((
                      'basemap-coordinates',
                      _draft.customCoordinates,
                    )),
                    initialValue: _draft.customCoordinates,
                    enabled: !_save.isLoading,
                    label: Text(tr('sim.basemap_coordinates')),
                    minWidth: constraints.maxWidth,
                    maxWidth: constraints.maxWidth,
                    options: [
                      for (final coordinates in BasemapCoordinates.values)
                        ShadOption(
                          value: coordinates,
                          child: Text(
                            tr('sim.basemap_crs.${coordinates.name}'),
                          ),
                        ),
                    ],
                    selectedOptionBuilder: (context, value) =>
                        Text(tr('sim.basemap_crs.${value.name}')),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(
                        () =>
                            _draft = _draft.copyWith(customCoordinates: value),
                      );
                    },
                  ),
            ),
            SizedBox(height: SimSpace.md),
            ShadInputFormField(
              key: const PageStorageKey('basemap-custom-attribution'),
              controller: _attribution,
              enabled: !_save.isLoading,
              label: Text(tr('sim.basemap_attribution')),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  _url.text.trim().isNotEmpty && value.trim().isEmpty
                  ? tr('sim.errors.basemap_attribution_required')
                  : null,
            ),
          ],
          SizedBox(height: SimSpace.md),
          Text(
            tr('sim.basemap_network_hint'),
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (_draft.provider == BasemapProvider.amap ||
              _draft.provider == BasemapProvider.baidu) ...[
            SizedBox(height: SimSpace.ms),
            Text(
              tr('sim.basemap_provider_warning'),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          if (_save case RequestFailure(:final failure)) ...[
            SizedBox(height: SimSpace.md),
            SimNotice(
              text: tr(
                failure.message == 'workspace_save_failed'
                    ? 'sim.save_failure'
                    : 'sim.errors.operation_failed',
              ),
              error: true,
            ),
          ],
        ],
      ),
    ),
  );
}
