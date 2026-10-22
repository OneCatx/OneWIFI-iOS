import 'package:flutter/material.dart';

import '../one/glass.dart';
import '../tokens/one_tokens.dart';
import 'glass_panel.dart';
import 'metric_card.dart';
import 'ow_accent.dart';
import 'system_controls.dart';

/// WEB `OwGlassPanel`：框头是独立标题行，正文不再跟标题抢同一字号。
///
/// 给 [tone] 时框头图标变成 WEB `panel-title-icon--teal/purple/amber/blue`
/// 那种着色方块，四个框一眼能分出来；不给则保持黑白线性图标。
final class OwSection extends StatelessWidget {
  const OwSection({
    required this.title,
    required this.child,
    this.icon,
    this.tone,
    this.desc,
    this.actions,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final String? desc;
  final IconData? icon;
  final PlateTone? tone;
  final Widget? actions;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassListCard(
      semanticLabel: semanticLabel ?? title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // WEB `.overview-card__head`：标题在左、动作钉在右上角同一行。
          // 动作多到放不下时在右侧自己折行，不把标题挤掉。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (icon != null && tone != null) ...<Widget>[
                PanelTitleIcon(icon: icon!, tone: tone!),
                const SizedBox(width: Glass.space8 + Glass.space2),
              ] else if (icon != null) ...<Widget>[
                SystemIcon(icon!, size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: Glass.space8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (actions != null) ...<Widget>[
                const SizedBox(width: Glass.space8),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actions!,
                  ),
                ),
              ],
            ],
          ),
          if (desc != null && desc!.isNotEmpty) ...<Widget>[
            const SizedBox(height: Glass.space4),
            Text(
              desc!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Glass.space16),
          child,
        ],
      ),
    );
  }
}

/// 框顶上的长铭牌横幅：左边一枚发光圆徽记，中间主副两行字，右边可挂一块牌。
/// 仪表盘「主机」、设置页账号、设备详情 SIM 都用它，色调全局统一青蓝。
final class HeroBanner extends StatelessWidget {
  const HeroBanner({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// 替代默认圆徽记的自定义左侧装饰（例如 SIM 芯片）。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Glass.radiusTile),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              OwAccent.teal.withValues(alpha: dark ? 0.22 : 0.16),
              OwAccent.blue.withValues(alpha: dark ? 0.14 : 0.10),
              Colors.transparent,
            ],
          ),
          border: Border.all(
            color: OwAccent.teal.withValues(alpha: dark ? 0.26 : 0.30),
            width: Glass.strokeWidth,
          ),
          borderRadius: BorderRadius.circular(Glass.radiusTile),
        ),
        child: Padding(
          padding: const EdgeInsets.all(OneSpacing.item + OneSpacing.micro),
          child: Row(
            children: <Widget>[
              leading ??
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OwAccent.teal.withValues(
                        alpha: dark ? 0.18 : 0.14,
                      ),
                      border: Border.all(
                        color: OwAccent.teal.withValues(alpha: 0.40),
                        width: Glass.strokeWidth,
                      ),
                      boxShadow: OwAccent.plateShadow(OwAccent.teal),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(OneSpacing.small),
                      child: SystemIcon(
                        icon,
                        size: 22,
                        color: OwAccent.ink(OwAccent.teal, dark),
                      ),
                    ),
                  ),
              const SizedBox(width: OneSpacing.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle case final sub?
                        when sub.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Glass.space2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: OneSpacing.small),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
