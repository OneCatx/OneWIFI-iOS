import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_panel.dart';
import '../domain/device.dart';

final class DiscoveredDeviceCard extends StatelessWidget {
  const DiscoveredDeviceCard({
    required this.device,
    required this.onRegister,
    super.key,
  });

  final DiscoveredDevice device;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasIssues = device.hasIssues;
    final isConfigured = device.configured;
    
    return Semantics(
      button: true,
      label: '${device.readerName}, ${isConfigured ? "已配置" : "未注册"}',
      child: GlassListCard(
        semanticLabel: 'Discovered device ${device.readerName}',
        padding: const EdgeInsets.all(OneSpacing.medium + OneSpacing.micro),
        onTap: isConfigured ? null : onRegister,
        selectedAccent: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CardHeadRow(
              icon: Icons.router_outlined,
              iconColor: isConfigured
                  ? theme.colorScheme.onSurface.withOpacity(0.5)
                  : theme.colorScheme.onSurface,
              title: device.readerName.isNotEmpty
                  ? device.readerName
                  : device.imei,
              trailingShare: 0.48,
              trailing: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Nameplate(
                      label: isConfigured ? '已配置' : '未注册',
                      tone: isConfigured
                          ? PlateTone.neutral
                          : PlateTone.blue,
                    ),
                    if (hasIssues) ...<Widget>[
                      const SizedBox(height: OneSpacing.micro),
                      Nameplate(
                        label: device.degraded ? '降级' : '有问题',
                        tone: PlateTone.red,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: OneSpacing.item + OneSpacing.micro),
            Wrap(
              spacing: OneSpacing.small,
              runSpacing: OneSpacing.small,
              children: <Widget>[
                Nameplate(
                  label: device.deviceType,
                  tone: PlateTone.purple,
                ),
                if (device.imei.isNotEmpty)
                  Nameplate(label: 'IMEI ${device.imei.substring(device.imei.length > 8 ? device.imei.length - 8 : 0)}'),
                if (device.networkCapable)
                  const Nameplate(label: '支持网络', tone: PlateTone.green),
                if (!device.networkCapable)
                  const Nameplate(label: '无网络能力', tone: PlateTone.neutral),
              ],
            ),
            if (device.discoveryIssue.isNotEmpty) ...<Widget>[
              const SizedBox(height: OneSpacing.small),
              Text(
                device.discoveryIssue,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (!isConfigured && !hasIssues) ...<Widget>[
              const SizedBox(height: OneSpacing.item),
              FilledButton.tonal(
                onPressed: onRegister,
                child: const Text('注册设备'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
