import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_panel.dart';
import '../../esim/domain/euicc_hardware.dart';
import '../domain/device.dart';

/// WEB `device-card`，设备页 / 短信页共用同一张：
/// 头行左边是设备名。右上角是连接状态，紧挨在下面是当前选中的卡名（如 One NZ）。
/// 品牌铭牌单独一行。每个槽位一块铭牌，槽位名和容量写在同一行；两个槽位才是两行。
final class FleetDeviceCard extends StatelessWidget {
  const FleetDeviceCard({
    required this.device,
    required this.onTap,
    this.hardware,
    this.selectedCardName = '',
    this.brandNameplate = '',
    this.selected = false,
    super.key,
  });

  final DeviceSnapshot device;
  final List<EuiccHardware>? hardware;

  /// 这台设备上当前启用的 profile 名字。空串表示还没读到。
  final String selectedCardName;

  /// 网关指定的品牌铭牌。国内实体卡是「国内卡」，只这一台，不走 eSIM 槽位。
  final String brandNameplate;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final chips = hardware ?? const <EuiccHardware>[];
    final forcedBrand = brandNameplate.trim();
    final domestic = forcedBrand == '国内卡';
    final nameplate = forcedBrand.isNotEmpty
        ? forcedBrand
        : chips.isEmpty
        ? unknownEuiccNameplate
        : chips.first.nameplate;
    final profileName = selectedCardName.trim();
    final line = lineStateOf(device);
    final corner = <Widget>[
      if (profileName.isNotEmpty)
        Nameplate(label: profileName, tone: PlateTone.teal),
    ];
    return _FleetCardFrame(
      name: device.name,
      semanticState: line.label,
      plate: Nameplate(label: line.label, tone: line.tone),
      cornerPlates: corner,
      selected: selected,
      onTap: onTap,
      children: <Widget>[
        const SizedBox(height: OneSpacing.item + OneSpacing.micro),
        Nameplate(
          label: nameplate,
          tone: chips.isEmpty ? PlateTone.neutral : PlateTone.purple,
        ),
        if (!domestic)
          for (final chip in chips) ...<Widget>[
          const SizedBox(height: OneSpacing.small),
          Nameplate(
            label: chip.slotLabel,
            detail: chip.hasCapacity ? '可用 ${chip.freeNvram}' : null,
          ),
        ],
      ],
    );
  }
}

/// 没有 [DeviceSnapshot] 时的同款卡（短信页「全部设备」、只知道名字的模组）：
/// 头行一样（右上角是在线/离线牌），下面只放调用方给的几块牌。
final class FleetSummaryCard extends StatelessWidget {
  const FleetSummaryCard({
    required this.name,
    required this.onTap,
    this.plates = const <String>[],
    this.online = true,
    this.selected = false,
    this.icon = Icons.smartphone_outlined,
    super.key,
  });

  final String name;
  final VoidCallback onTap;
  final List<String> plates;
  final bool online;
  final bool selected;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _FleetCardFrame(
    name: name,
    semanticState: online ? '在线' : '离线',
    plate: Nameplate(label: online ? '在线' : '离线', ready: online),
    selected: selected,
    onTap: onTap,
    icon: icon,
    children: <Widget>[
      if (plates.isNotEmpty) ...<Widget>[
        const SizedBox(height: OneSpacing.item + OneSpacing.micro),
        Wrap(
          spacing: OneSpacing.small,
          runSpacing: OneSpacing.small,
          children: <Widget>[
            for (final plate in plates) Nameplate(label: plate),
          ],
        ),
      ],
    ],
  );
}

final class _FleetCardFrame extends StatelessWidget {
  const _FleetCardFrame({
    required this.name,
    required this.semanticState,
    required this.plate,
    this.cornerPlates = const <Widget>[],
    required this.selected,
    required this.onTap,
    required this.children,
    this.icon = Icons.smartphone_outlined,
  });

  final String name;
  final String semanticState;
  final Widget plate;
  final List<Widget> cornerPlates;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> children;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = selected
        ? OwAccent.ink(OwAccent.green, theme.brightness == Brightness.dark)
        : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, $semanticState',
      child: GlassListCard(
        semanticLabel: 'Device $name',
        padding: const EdgeInsets.all(OneSpacing.medium + OneSpacing.micro),
        onTap: onTap,
        selectedAccent: selected ? OwAccent.green : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CardHeadRow(
              icon: icon,
              iconColor: iconColor,
              title: name,
              trailingShare: 0.48,
              trailing: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    plate,
                    for (final corner in cornerPlates) ...<Widget>[
                      const SizedBox(height: OneSpacing.micro),
                      corner,
                    ],
                  ],
                ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 「是 VoWiFi、蜂窝驻网，还是数据网络」——各走各的牌，已驻网不再误标成无线路。
({String label, PlateTone tone}) lineStateOf(DeviceSnapshot device) {
  if (device.vowifiActive) {
    return (label: 'VoWiFi 在线', tone: PlateTone.green);
  }
  if (device.cellularCamped) {
    return (label: '蜂窝驻留', tone: PlateTone.green);
  }
  if (device.networkConnected) {
    return (label: '数据网络在线', tone: PlateTone.blue);
  }
  if (device.controlOnline) {
    return (label: '无线路', tone: PlateTone.blue);
  }
  return (label: '未接入', tone: PlateTone.neutral);
}
