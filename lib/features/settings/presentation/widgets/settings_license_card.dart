import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsLicenseCard extends StatelessWidget {
  const SettingsLicenseCard({
    required this.license,
    required this.controller,
    required this.busy,
    required this.onActivate,
    this.onDeactivate,
    this.gatewayLicense,
    super.key,
  });

  final ProductLicense license;
  final GatewayLicenseStatus? gatewayLicense;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback? onActivate;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return OwSection(
      title: '授权',
      icon: Icons.key_outlined,
      tone: PlateTone.blue,
      desc: '同一张码可激活软路由和安卓各一台。向销售获取。',
      actions: Nameplate(
        label: license.isActive
            ? (license.membershipBadge.isEmpty
                  ? '已激活'
                  : '已激活 · ${license.membershipBadge}')
            : '未激活',
        ready: license.isActive,
      ),
      child: Column(
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
          if (!license.isActive) ...<Widget>[
            ObscurableField(
              key: const Key('settings-license-key'),
              controller: controller,
              enabled: !busy && onActivate != null,
              labelText: '激活码',
              hintText: 'XXXX-XXXX-XXXX-XXXX',
              revealLabel: '激活码',
            ),
            const SizedBox(height: OneSpacing.item),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassActionButton(
                icon: Icons.key_outlined,
                label: busy ? '绑定中…' : '激活',
                busy: busy,
                onPressed: onActivate,
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: GlassActionButton(
                key: const Key('settings-license-deactivate'),
                icon: Icons.link_off_outlined,
                label: busy ? '解除中…' : '解除激活',
                busy: busy,
                onPressed: onDeactivate,
              ),
            ),
        ],
      ),
    );
  }
}
