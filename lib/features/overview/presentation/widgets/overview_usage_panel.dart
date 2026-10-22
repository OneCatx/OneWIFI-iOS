import 'package:flutter/material.dart';

import '../../../../design/theme/one_theme.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/overview.dart';
import 'overview_format.dart';

final class OverviewUsagePanel extends StatelessWidget {
  const OverviewUsagePanel({
    required this.host,
    required this.stale,
    super.key,
  });

  final HostOverview host;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return OwSection(
      title: '占用',
      icon: Icons.insights_outlined,
      tone: PlateTone.purple,
      desc: stale ? '上次的数据' : null,
      child: SoftLabelGrid(
        children: <Widget>[
          _GaugeTile(
            title: 'CPU',
            percent: host.cpuPercent,
            sub: overviewFallback(host.cpuModel),
            tone: PlateTone.green,
          ),
          _GaugeTile(
            title: '内存',
            percent: host.memoryPercent,
            sub:
                '${overviewBytes(host.memoryUsedBytes)} / ${overviewBytes(host.memoryTotalBytes)}',
            tone: PlateTone.blue,
          ),
          _GaugeTile(
            title: '磁盘',
            percent: host.diskPercent,
            sub: '根分区',
            tone: PlateTone.purple,
          ),
          SoftLabel(
            title: '网络',
            value: '↓ ${overviewRate(host.netRxBps)}',
            sub: '↑ ${overviewRate(host.netTxBps)}',
            mono: true,
          ),
        ],
      ),
    );
  }
}

/// 占用瓷片：大号百分比 + 着色细进度条 + 一行灰字，比一列文字更像仪表。
final class _GaugeTile extends StatelessWidget {
  const _GaugeTile({
    required this.title,
    required this.percent,
    required this.sub,
    required this.tone,
  });

  final String title;
  final double percent;
  final String sub;
  final PlateTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = OneTheme.isDark(theme);
    final accent = OwAccent.of(tone, theme.colorScheme);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: OneSpacing.nano),
        Text(
          overviewPercent(percent),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: OwAccent.ink(accent, dark),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: OneSpacing.tight),
        ThinProgress(value: percent, tone: tone),
        const SizedBox(height: OneSpacing.micro),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
