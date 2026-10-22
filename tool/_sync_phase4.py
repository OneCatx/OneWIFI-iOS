import pathlib
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')

def write(rel, text):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8', newline='\n')
    print('WROTE', rel)

# SMS auto-clear tiles
write('lib/features/settings/presentation/widgets/settings_sms_tiles.dart', r'''import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsSmsTiles extends StatelessWidget {
  const SettingsSmsTiles({
    required this.settings,
    required this.busy,
    required this.onChanged,
    super.key,
  });

  final SmsModemSettings settings;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = settings.autoClearModemStorage;
    return OwSection(
      title: '自动清理模组短信存储',
      icon: Icons.sms_outlined,
      tone: PlateTone.blue,
      desc: '同步成功后删除模组 SM/ME 副本；网页记录仍保留。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: GlassActionButton(
                  key: const Key('sms-auto-clear-on'),
                  icon: Icons.check_circle_outline,
                  label: '开启',
                  busy: busy && enabled,
                  onPressed: (busy || onChanged == null)
                      ? null
                      : () => onChanged!(true),
                ),
              ),
              const SizedBox(width: OneSpacing.item),
              Expanded(
                child: GlassActionButton(
                  key: const Key('sms-auto-clear-off'),
                  icon: Icons.cancel_outlined,
                  label: '关闭',
                  busy: busy && !enabled,
                  onPressed: (busy || onChanged == null)
                      ? null
                      : () => onChanged!(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: OneSpacing.item),
          Text(
            enabled
                ? '当前：开启（默认）。模组 ME 通常只有几十格。'
                : '当前：关闭。仍会同步到数据库，但不删模组原件，邮箱满了可能挡新短信。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
''')

# Patch license card to show gateway status
lic = (root/'lib/features/settings/presentation/widgets/settings_license_card.dart').read_text(encoding='utf-8')
if 'gatewayLicense' not in lic:
    lic = lic.replace(
        '''  const SettingsLicenseCard({
    required this.license,
    required this.controller,
    required this.busy,
    required this.onActivate,
    super.key,
  });

  final ProductLicense license;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback? onActivate;''',
        '''  const SettingsLicenseCard({
    required this.license,
    required this.controller,
    required this.busy,
    required this.onActivate,
    this.gatewayLicense,
    super.key,
  });

  final ProductLicense license;
  final GatewayLicenseStatus? gatewayLicense;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback? onActivate;''',
    )
    # add gateway status line after Nameplate section / before ObscurableField
    marker = '      child: Column(\n        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: <Widget>[\n          ObscurableField('
    insert = '''      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (gatewayLicense case final GatewayLicenseStatus gw) ...<Widget>[
            Text(
              gw.activated
                  ? '网关/router 席：已激活${gw.edition.isEmpty ? '' : ' · ${gw.edition}'}'
                  : '网关/router 席：未激活',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: OneSpacing.item),
          ],
          ObscurableField('''
    if marker in lic:
        lic = lic.replace(marker, insert)
    (root/'lib/features/settings/presentation/widgets/settings_license_card.dart').write_text(lic, encoding='utf-8', newline='\n')
    print('license card patched')

# settings_screen
ss = (root/'lib/features/settings/presentation/settings_screen.dart').read_text(encoding='utf-8')
if 'SettingsSmsTiles' not in ss:
    ss = ss.replace(
        "import 'widgets/settings_license_card.dart';",
        "import 'widgets/settings_license_card.dart';\nimport 'widgets/settings_sms_tiles.dart';",
    )
    ss = ss.replace(
        '''              SettingsLicenseCard(
                license: snap.license,
                controller: _license,
                busy: settings?.licenseAction.status == ActionStatus.submitting,
                onActivate: settings == null
                    ? null
                    : () => settings.activateLicense(_license.text),
              ),
              const SizedBox(height: OneSpacing.medium),''',
        '''              SettingsLicenseCard(
                license: snap.license,
                gatewayLicense: snap.gatewayLicense,
                controller: _license,
                busy: settings?.licenseAction.status == ActionStatus.submitting,
                onActivate: settings == null
                    ? null
                    : () => settings.activateLicense(_license.text),
              ),
              const SizedBox(height: OneSpacing.medium),
              SettingsSmsTiles(
                settings: snap.smsModem,
                busy: settings?.smsModemAction.status == ActionStatus.submitting,
                onChanged: settings == null ? null : settings.setSmsAutoClear,
              ),
              const SizedBox(height: OneSpacing.medium),''',
    )
    (root/'lib/features/settings/presentation/settings_screen.dart').write_text(ss, encoding='utf-8', newline='\n')
    print('settings screen patched')

print('ui ok')
