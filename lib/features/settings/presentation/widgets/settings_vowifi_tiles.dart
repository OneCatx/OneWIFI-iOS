import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsVowifiTiles extends StatelessWidget {
  const SettingsVowifiTiles({
    required this.settings,
    required this.busy,
    required this.onChanged,
    super.key,
  });

  final VowifiMtuSettings settings;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = settings.mtuCompatibility;
    return OwSection(
      title: 'VoWiFi MTU 兼容模式',
      icon: Icons.wifi_tethering,
      tone: PlateTone.blue,
      desc: '改善部分系统因网络包大小限制导致的注册失败',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: GlassActionButton(
                  key: const Key('vowifi-mtu-on'),
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
                  key: const Key('vowifi-mtu-off'),
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
                ? '当前：开启。适用于所有设备，保存后请重连 VoWiFi。'
                : '当前：关闭（默认）。遇到 MTU 不足导致的 VoWiFi 连接问题时可尝试开启。此设置适用于所有设备，保存后请重连 VoWiFi。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
