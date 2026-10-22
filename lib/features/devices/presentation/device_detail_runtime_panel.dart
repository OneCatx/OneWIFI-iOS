part of 'device_detail_view.dart';

/// 运行状态只留一个框：走 VoWiFi 时画 VoWiFi，否则画数据。
final class _RuntimePanel extends StatelessWidget {
  const _RuntimePanel({required this.device, required this.onReconnect});

  final DeviceSnapshot device;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final runtime = device.runtime;
    final onVowifi = _onVowifi(device);
    final hero = onVowifi ? _wificallLabel(device) : _dataLabel(device);
    return OwSection(
      title: '运行状态',
      icon: Icons.insights_outlined,
      tone: PlateTone.teal,
      actions: GlassActionButton(
        icon: Icons.sync,
        label: '重连 VoWiFi',
        onPressed: device.vowifiEnabled ? onReconnect : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (device.smsStorage
              case final DeviceSmsStorage storage) ...<Widget>[
            GlassTile(
              child: Text(
                '模组短信 SM ${storage.sm.used}/${storage.sm.total} · ME ${storage.me.used}/${storage.me.total}',
              ),
            ),
            const SizedBox(height: OneSpacing.medium),
          ],
          const SizedBox(height: OneSpacing.small),
          GlassTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _GroupLabel(text: onVowifi ? 'WiFi Call' : '数据'),
                const SizedBox(height: OneSpacing.small),
                Center(
                  child: Nameplate(
                    label: hero.label,
                    hero: true,
                    ready: hero.tone == PlateTone.green,
                    tone: hero.tone,
                  ),
                ),
                if (!onVowifi && device.radioSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OneSpacing.item),
                  Text(
                    device.radioSummary,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OneSpacing.medium),
          GlassTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _GroupLabel(text: '当前进度'),
                const SizedBox(height: OneSpacing.small),
                StageRow(stages: _stagesOf(device), semanticLabel: '当前进度'),
              ],
            ),
          ),
          if (runtime.dataPlane.isNotEmpty ||
              runtime.lastReason.isNotEmpty ||
              runtime.errorCategory.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.medium),
            GlassTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _GroupLabel(text: '详情'),
                  const SizedBox(height: OneSpacing.small),
                  if (runtime.dataPlane.isNotEmpty) ...<Widget>[
                    _DetailRow(label: '数据平面', value: runtime.dataPlane),
                    const SizedBox(height: OneSpacing.small),
                  ],
                  if (runtime.lastReason.isNotEmpty) ...<Widget>[
                    _DetailRow(label: '最后原因', value: runtime.lastReason),
                    const SizedBox(height: OneSpacing.small),
                  ],
                  if (runtime.errorCategory.isNotEmpty)
                    _DetailRow(label: '错误分类', value: runtime.errorCategory),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// WEB `detail-row`：左标签、右等宽值，一行一项。
final class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: OneSpacing.item),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// 照搬 WEB 运行状态框的大铭牌：全部就绪→荧光绿；失败→红；有阶段就绪→琥珀"接入中"；
/// 其余保持中性，不用颜色误报状态。
bool _onVowifi(DeviceSnapshot device) {
  final runtime = device.runtime;
  return device.vowifiActive ||
      runtime.allReady ||
      runtime.tunnelReady ||
      runtime.imsReady ||
      runtime.smsReady;
}

({String label, PlateTone tone}) _dataLabel(DeviceSnapshot device) {
  if (device.cellularCamped) {
    final status = device.radioStatus.trim();
    return (
      label: status.isEmpty ? '蜂窝驻留' : status,
      tone: PlateTone.green,
    );
  }
  if (device.networkConnected) {
    return (label: '数据网络在线', tone: PlateTone.blue);
  }
  return (label: '数据未接入', tone: PlateTone.neutral);
}

({String label, PlateTone tone}) _wificallLabel(DeviceSnapshot device) {
  final runtime = device.runtime;
  if (runtime.allReady) {
    return (label: 'WiFi-Calling · 全部就绪', tone: PlateTone.green);
  }
  if (runtime.phase == DeviceRuntimePhase.failed) {
    return (label: 'VoWiFi 未就绪', tone: PlateTone.red);
  }
  if (runtime.simReady || runtime.accessReady || runtime.tunnelReady) {
    return (label: 'WiFi-Calling · 接入中', tone: PlateTone.blue);
  }
  return (label: 'WiFi-Calling', tone: PlateTone.neutral);
}

/// SIM→Access→Tunnel→IMS→卡策略 五段进度：已就绪亮绿；失败时下一段标红；
/// 在线且未失败时下一段脉冲；离线一律灰。
List<(String, StageState)> _stagesOf(DeviceSnapshot device) {
  final runtime = device.runtime;
  final flags = <(String, bool)>[
    ('SIM', runtime.simReady),
    ('Access', runtime.accessReady),
    ('Tunnel', runtime.tunnelReady),
    ('IMS', runtime.imsReady),
    ('卡策略', runtime.smsReady),
  ];
  final failed = runtime.phase == DeviceRuntimePhase.failed;
  var nextMarked = false;
  final stages = <(String, StageState)>[];
  for (final (label, ready) in flags) {
    if (ready) {
      stages.add((label, StageState.ready));
    } else if (!nextMarked && device.controlOnline) {
      nextMarked = true;
      stages.add((label, failed ? StageState.failed : StageState.active));
    } else {
      stages.add((label, StageState.pending));
    }
  }
  return stages;
}

/// 面板内分组小标签：给"当前进度 / 详情"这类块一个抬头，避免一堆芯片悬空。
final class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
