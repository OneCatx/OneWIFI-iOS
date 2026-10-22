import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/overview.dart';
import 'overview_format.dart';

final class OverviewHostPanel extends StatelessWidget {
  const OverviewHostPanel({required this.host, required this.stale, super.key});

  final HostOverview host;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return OwSection(
      semanticLabel: '主机性能',
      title: '主机',
      icon: Icons.router_outlined,
      tone: PlateTone.teal,
      desc: stale ? '上次的数据' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 全局同款长铭牌：横幅当「主机名牌」，下面才是两列瓷片。
          HeroBanner(
            icon: Icons.router_outlined,
            title: host.boardModel.isEmpty ? 'OneWIFI 主机' : host.boardModel,
            subtitle: host.cpuModel.isEmpty ? 'OneWIFI' : host.cpuModel,
            trailing: const Nameplate(label: '在线', ready: true),
          ),
          const SizedBox(height: OneSpacing.item),
          SoftLabelGrid(
            children: <Widget>[
              const SoftLabel(title: '系统', value: 'OneWIFI'),
              SoftLabel(title: '机型', value: overviewFallback(host.boardModel)),
              SoftLabel(title: 'CPU', value: overviewFallback(host.cpuModel)),
              SoftLabel(
                title: '内存总量',
                value: overviewBytes(host.memoryTotalBytes),
                mono: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
