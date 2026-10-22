import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../state/sms_controller.dart';

final class SmsOtpWatchTile extends StatelessWidget {
  const SmsOtpWatchTile({required this.controller, super.key});

  static const Key switchKey = Key('sms-otp-watch-switch');

  final SmsController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.otpWatchAvailable) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hit = controller.lastOtpHit;
    return GlassTile(
      semanticLabel: '验证码推送',
      child: Row(
        children: <Widget>[
          SystemIcon(
            Icons.pin_outlined,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: OneSpacing.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '验证码推送',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: OneSpacing.nano),
                Text(
                  hit == null
                      ? '新验证码会通知并复制到剪贴板。App 在后台时也能盯，划掉进程就停。'
                      : '已复制 ${hit.code}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: switchKey,
            value: controller.otpWatchEnabled,
            onChanged: controller.setOtpWatchEnabled,
          ),
        ],
      ),
    );
  }
}
