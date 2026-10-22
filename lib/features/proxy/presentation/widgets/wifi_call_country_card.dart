import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/glass_panel.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../domain/wifi_call_group.dart';
import '../../domain/wifi_selector_catalog.dart';
import 'wifi_flag_mark.dart';
import 'wifi_node_status.dart';

final class WifiCallCountryCard extends StatelessWidget {
  const WifiCallCountryCard({
    required this.group,
    required this.onTap,
    this.onRemove,
    this.probing = false,
    super.key,
  });

  /// 原 136 的 60%。
  static const double extent = 82;

  final WifiCallGroup group;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool probing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = wifiCurrentNode(group);
    final badge = current == null
        ? '${group.aliveCount}/${group.totalCount}'
        : wifiNodeBadge(current, probing: probing);
    final tone = current == null
        ? (group.aliveCount > 0 ? PlateTone.green : PlateTone.red)
        : wifiNodeTone(current);
    final showPlate =
        current == null || wifiNodeShowsPlate(current, probing: probing);
    return Semantics(
      button: true,
      label: '${group.countryName} ${group.groupName}',
      child: GlassListCard(
        semanticLabel: '${group.countryName} ${group.groupName}',
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: WifiFlagWatermark(
                countryCode: group.countryCode,
                flagEmoji: group.flagEmoji,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OneSpacing.small,
                OneSpacing.small,
                OneSpacing.small,
                OneSpacing.micro,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CardHeadRow(
                    title: group.countryName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    trailingShare: 0.46,
                    trailing: showPlate
                        ? <Widget>[
                            Nameplate(
                              label: badge,
                              ready: tone == PlateTone.green,
                              tone: tone,
                              lifted: true,
                            ),
                          ]
                        : const <Widget>[],
                  ),
                  const SizedBox(height: OneSpacing.nano),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        group.now.isEmpty
                            ? '未选择'
                            : WifiSelectorCatalog.stripLeadingDecor(group.now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton(
                  key: ValueKey<String>('proxy-unpin-${group.countryCode}'),
                  tooltip: '移出一级',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: onRemove,
                  icon: SystemIcon(
                    Icons.close,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class WifiCallPlusCard extends StatelessWidget {
  const WifiCallPlusCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '更多国家',
      child: GlassListCard(
        semanticLabel: '更多国家',
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SystemIcon(Icons.add, size: 22, color: muted),
              const SizedBox(height: OneSpacing.nano),
              Text(
                '更多',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
