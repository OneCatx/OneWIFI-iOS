import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/certificate_trust_dialog.dart';
import '../../../../core/config/base_url_policy.dart';
import '../../../../core/state/action_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/choice_toggle.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../../proxy/state/mihomo_connection_controller.dart';

final class SettingsMihomoForm extends StatefulWidget {
  const SettingsMihomoForm({required this.controller, super.key});

  static const Key hostFieldKey = Key('settings-mihomo-host');
  static const Key portFieldKey = Key('settings-mihomo-port');
  static const Key httpsSwitchKey = Key('settings-mihomo-https');
  static const Key secretFieldKey = Key('settings-mihomo-secret');
  static const Key connectTargetKey = Key('settings-mihomo-connect');

  final MihomoConnectionController controller;

  @override
  State<SettingsMihomoForm> createState() => _SettingsMihomoFormState();
}

final class _SettingsMihomoFormState extends State<SettingsMihomoForm> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _secret = TextEditingController();
  var _https = false;
  var _hydrated = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.hydrate();
    });
  }

  @override
  void didUpdateWidget(SettingsMihomoForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _hydrated = false;
      widget.controller.hydrate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _host.dispose();
    _port.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    final origin = widget.controller.origin;
    if (!_hydrated) {
      if (origin != null) {
        final parts = BaseUrlPolicy.split(origin);
        _host.text = parts.host;
        _port.text = parts.port;
        _https = parts.https;
        _secret.text = widget.controller.secret;
      }
      _hydrated = true;
    }
    setState(() {});
  }

  Future<void> _configureCertificate() async {
    final connections = widget.controller.connections;
    if (connections == null) return;
    try {
      final origin = BaseUrlPolicy.fromHostAndPort(
        host: _host.text,
        port: _port.text,
        https: true,
      );
      await showCertificateTrustDialog(
        context: context,
        connections: connections,
        origin: origin,
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        widget.controller.connectAction.status == ActionStatus.submitting;
    final status = widget.controller.status;
    return OwSection(
      title: 'Mihomo',
      icon: Icons.hub_outlined,
      tone: PlateTone.teal,
      desc: '自己填主机和端口。没有密钥就留空，连上再到代理页选节点。',
      actions: Nameplate(
        label: widget.controller.connected ? '已连接' : '未连接',
        ready: widget.controller.connected,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  key: SettingsMihomoForm.hostFieldKey,
                  controller: _host,
                  enabled: !busy,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '主机 / IP',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: OneSpacing.item),
              Expanded(
                child: TextField(
                  key: SettingsMihomoForm.portFieldKey,
                  controller: _port,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: OneSpacing.item),
          Text(
            'HTTPS',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: OneSpacing.small),
          ChoiceToggle(
            key: SettingsMihomoForm.httpsSwitchKey,
            value: _https,
            onChanged: busy
                ? null
                : (value) => setState(() => _https = value),
          ),
          const SizedBox(height: OneSpacing.item),
          if (_https && widget.controller.connections != null)
            TextButton.icon(
              onPressed: busy ? null : _configureCertificate,
              icon: const SystemIcon(Icons.verified_user_outlined),
              label: const Text('证书指纹'),
            ),
          ObscurableField(
            key: SettingsMihomoForm.secretFieldKey,
            controller: _secret,
            enabled: !busy,
            labelText: '密钥',
            hintText: '没有就留空',
            revealLabel: '密钥',
          ),
          if (status.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.small),
            Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.controller.connected
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: OneSpacing.item),
          Align(
            alignment: Alignment.centerLeft,
            child: GlassActionButton(
              key: SettingsMihomoForm.connectTargetKey,
              icon: Icons.link,
              label: busy ? '连接中…' : '连接',
              busy: busy,
              onPressed: busy
                  ? null
                  : () => widget.controller.connect(
                      host: _host.text,
                      port: _port.text,
                      https: _https,
                      secret: _secret.text,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
