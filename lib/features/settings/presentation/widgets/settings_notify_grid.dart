import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsNotifyGrid extends StatelessWidget {
  const SettingsNotifyGrid({
    required this.notifications,
    required this.enabled,
    required this.onOpen,
    super.key,
  });

  final NotificationSettings notifications;
  final bool enabled;
  final ValueChanged<NotifyChannel> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final channel in NotifyChannel.values) ...<Widget>[
          GlassTile(
            key: Key('settings-notify-${channel.apiName}'),
            onTap: enabled ? () => onOpen(channel) : null,
            semanticLabel: channel.label,
            child: Row(
              children: <Widget>[
                Expanded(child: Text(channel.label)),
                Text(
                  notifications.of(channel).enabled ? '已开启' : '已关闭',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (channel != NotifyChannel.values.last)
            const SizedBox(height: OneSpacing.small),
        ],
      ],
    );
  }
}
