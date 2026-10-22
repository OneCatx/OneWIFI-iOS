import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsQuotaForm extends StatelessWidget {
  const SettingsQuotaForm({
    required this.quota,
    required this.deviceLimit,
    required this.smsLimit,
    required this.busy,
    required this.onSaveDevice,
    required this.onSaveSms,
    super.key,
  });

  final DeveloperQuota quota;
  final TextEditingController deviceLimit;
  final TextEditingController smsLimit;
  final bool busy;
  final VoidCallback? onSaveDevice;
  final VoidCallback? onSaveSms;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: deviceLimit,
          keyboardType: TextInputType.number,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: '设备上限（1–${quota.maxDeviceLimit}）',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: OneSpacing.item),
        TextField(
          controller: smsLimit,
          keyboardType: TextInputType.number,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: '短信每小时上限（1–${quota.maxSmsHourlyLimit}）',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: OneSpacing.item),
        Wrap(
          spacing: OneSpacing.small,
          runSpacing: OneSpacing.small,
          children: <Widget>[
            GlassActionButton(
              label: '保存设备配额',
              busy: busy,
              onPressed: onSaveDevice,
            ),
            GlassActionButton(
              label: '保存短信限额',
              busy: busy,
              onPressed: onSaveSms,
            ),
          ],
        ),
      ],
    );
  }
}
