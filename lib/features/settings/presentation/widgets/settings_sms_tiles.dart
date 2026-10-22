import 'package:flutter/material.dart';

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
