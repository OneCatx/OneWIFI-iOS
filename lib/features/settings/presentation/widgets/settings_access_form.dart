import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsAccessForm extends StatelessWidget {
  const SettingsAccessForm({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
    required this.mode,
    required this.onMode,
    required this.cidrs,
    required this.trustProxy,
    required this.onTrustProxy,
    required this.proxyCidrs,
    required this.clientIp,
    required this.clientAllowed,
    required this.passwordBusy,
    required this.securityBusy,
    required this.onChangePassword,
    required this.onSaveSecurity,
    required this.changePasswordKey,
    required this.saveSecurityKey,
    super.key,
  });

  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmPassword;
  final AccessMode mode;
  final ValueChanged<AccessMode> onMode;
  final TextEditingController cidrs;
  final bool trustProxy;
  final ValueChanged<bool> onTrustProxy;
  final TextEditingController proxyCidrs;
  final String clientIp;
  final bool clientAllowed;
  final bool passwordBusy;
  final bool securityBusy;
  final VoidCallback? onChangePassword;
  final VoidCallback? onSaveSecurity;
  final Key changePasswordKey;
  final Key saveSecurityKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ObscurableField(
          controller: currentPassword,
          enabled: onChangePassword != null,
          labelText: '当前密码',
          revealLabel: '当前密码',
        ),
        const SizedBox(height: OneSpacing.item),
        ObscurableField(
          controller: newPassword,
          enabled: onChangePassword != null,
          labelText: '新密码（≥10）',
          revealLabel: '新密码',
        ),
        const SizedBox(height: OneSpacing.item),
        ObscurableField(
          controller: confirmPassword,
          enabled: onChangePassword != null,
          labelText: '确认新密码',
          revealLabel: '确认新密码',
        ),
        const SizedBox(height: OneSpacing.item),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '访问模式',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AccessMode>(
              value: mode,
              isExpanded: true,
              items: const <DropdownMenuItem<AccessMode>>[
                DropdownMenuItem(
                  value: AccessMode.internal,
                  child: Text('仅内网'),
                ),
                DropdownMenuItem(
                  value: AccessMode.public,
                  child: Text('公网 + 允许列表'),
                ),
              ],
              onChanged: onSaveSecurity == null
                  ? null
                  : (value) {
                      if (value != null) onMode(value);
                    },
            ),
          ),
        ),
        const SizedBox(height: OneSpacing.item),
        TextField(
          controller: cidrs,
          minLines: 3,
          maxLines: 5,
          enabled: onSaveSecurity != null,
          decoration: const InputDecoration(
            labelText: '额外允许 CIDR（每行一条）',
            hintText: '10.0.0.0/8',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('信任反向代理头'),
          value: trustProxy,
          onChanged: onSaveSecurity == null ? null : onTrustProxy,
        ),
        TextField(
          controller: proxyCidrs,
          minLines: 2,
          maxLines: 4,
          enabled: onSaveSecurity != null,
          decoration: const InputDecoration(
            labelText: '可信反代 CIDR（每行一条；不填则忽略代理头）',
            hintText: '10.0.0.1/32',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: OneSpacing.small),
        Text(
          '当前客户端 ${clientIp.isEmpty ? '—' : clientIp} · ${clientAllowed ? '允许' : '拒绝'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: OneSpacing.item),
        Wrap(
          spacing: OneSpacing.small,
          runSpacing: OneSpacing.small,
          children: <Widget>[
            GlassActionButton(
              key: changePasswordKey,
              icon: Icons.password,
              label: passwordBusy ? '提交中…' : '改密并退出',
              busy: passwordBusy,
              onPressed: onChangePassword,
            ),
            GlassActionButton(
              key: saveSecurityKey,
              icon: Icons.security_outlined,
              label: securityBusy ? '保存中…' : '保存访问策略',
              busy: securityBusy,
              onPressed: onSaveSecurity,
            ),
          ],
        ),
      ],
    );
  }
}
