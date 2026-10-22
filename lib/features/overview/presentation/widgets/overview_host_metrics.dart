import 'package:flutter/material.dart';

import '../../../../design/widgets/console_layout.dart';
import '../../domain/overview.dart';
import 'overview_format.dart';

final class OverviewHostMetrics extends StatelessWidget {
  const OverviewHostMetrics({required this.host, super.key});

  final HostOverview host;

  @override
  Widget build(BuildContext context) {
    return MetricRow(
      children: <Widget>[
        MetricCard(
          label: 'CPU',
          value: overviewPercent(host.cpuPercent),
          sub: '主机占用',
          icon: Icons.memory,
          tone: MetricTone.green,
        ),
        MetricCard(
          label: '内存',
          value: overviewPercent(host.memoryPercent),
          sub: '系统内存',
          icon: Icons.insights_outlined,
          tone: MetricTone.blue,
        ),
        MetricCard(
          label: '磁盘',
          value: overviewPercent(host.diskPercent),
          sub: '根分区',
          icon: Icons.storage_outlined,
          tone: MetricTone.purple,
        ),
        MetricCard(
          label: '网络',
          value: overviewRate(host.netRxBps),
          sub:
              '↓ ${overviewRate(host.netRxBps)} · ↑ ${overviewRate(host.netTxBps)}',
          icon: Icons.cell_tower_outlined,
          tone: MetricTone.blue,
        ),
      ],
    );
  }
}
