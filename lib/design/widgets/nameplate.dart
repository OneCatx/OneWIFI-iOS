import 'package:flutter/material.dart';

import '../one/glass.dart';
import '../tokens/one_tokens.dart';
import 'ow_accent.dart';
import 'system_controls.dart';

/// WEB `overview-badge` / 设备铭牌：小圆点 + 短词，不是一行长文。
///
/// [ready] 为真时走 WEB `.device-card__tag.is-online` 的「已连接」样式：
/// 牌面只透一点绿、描边淡绿、几乎不发光，亮度全在那颗 8px 小圆点上
/// （`0 0 12px rgba(52,211,153,.95)`）。要别的语义色用 [tone]。
/// [hero] 是运行状态框顶上那块大牌（WEB `overview-badge--hero`）。
/// [lifted] 用在国旗等花底上：不透明底 + 投影，字才压得住旗面。
final class Nameplate extends StatelessWidget {
  const Nameplate({
    required this.label,
    this.detail,
    this.ready = false,
    this.compact = true,
    this.hero = false,
    this.lifted = false,
    this.tone,
    super.key,
  });

  final String label;

  /// 和 [label] 同一行、写在同一块铭牌里。空则只画 [label]。
  final String? detail;
  final bool ready;
  final bool compact;
  final bool hero;
  final bool lifted;
  final PlateTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final scheme = theme.colorScheme;
    final resolvedTone = tone ?? (ready ? PlateTone.green : PlateTone.neutral);
    final lit = resolvedTone != PlateTone.neutral;
    final accent = OwAccent.of(resolvedTone, scheme);
    final fill = lifted
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.32),
            const Color(0xF2141414),
          )
        : lit
        ? accent.withValues(alpha: dark ? 0.12 : 0.10)
        : Glass.fill(scheme, dark);
    final stroke = lifted
        ? accent.withValues(alpha: 0.78)
        : lit
        ? accent.withValues(alpha: dark ? 0.24 : 0.32)
        : Glass.stroke(scheme, dark);
    final ink = lifted
        ? Colors.white
        : lit
        ? OwAccent.ink(accent, dark)
        : scheme.onSurface;
    final dot = lit ? accent : scheme.onSurfaceVariant.withValues(alpha: 0.55);
    final textStyle =
        (hero ? theme.textTheme.bodyMedium : theme.textTheme.labelSmall)
            ?.copyWith(
              color: ink,
              fontWeight: hero
                  ? FontWeight.w600
                  : lifted
                  ? FontWeight.w700
                  : FontWeight.w500,
              letterSpacing: hero ? 0.1 : null,
              shadows: lifted
                  ? const <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            );
    final horizontal = hero
        ? Glass.space16
        : compact
        ? Glass.space8
        : Glass.space12;
    final vertical = hero
        ? Glass.space8 + Glass.space2
        : compact
        ? Glass.space4
        : Glass.space8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: hero ? 320 : 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(
            hero ? Glass.radiusTile : Glass.radiusChip,
          ),
          border: Border.all(color: stroke, width: Glass.strokeWidth),
          boxShadow: lifted
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : lit
              ? OwAccent.plateShadow(accent)
              : Glass.shadow(dark),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: vertical,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: hero ? 8 : 6,
                height: hero ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: lit ? OwAccent.dotGlow(accent, dark) : null,
                ),
              ),
              SizedBox(width: hero ? Glass.space8 : Glass.space6),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                    if (detail != null &&
                        detail!.trim().isNotEmpty) ...<Widget>[
                      SizedBox(width: hero ? Glass.space8 : Glass.space6),
                      Flexible(
                        child: Text(
                          detail!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ink.withValues(alpha: 0.82),
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片头行：可选图标 + 标题 ……… 右上角一块或几块牌。
///
/// 牌钉在右边、最多占 [trailingShare] 的宽度，标题吃掉其余并截断；
/// 320dp + 200% 字号时牌自己截断而不是把行撑爆。设备卡 / 短信联系人卡 /
/// 保号卡的头行都是这一种，别再各写一个 Row。
final class CardHeadRow extends StatelessWidget {
  const CardHeadRow({
    required this.title,
    this.icon,
    this.iconColor,
    this.trailing = const <Widget>[],
    this.trailingShare = 0.55,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.style,
    super.key,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final List<Widget> trailing;
  final double trailingShare;
  final CrossAxisAlignment crossAxisAlignment;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = constraints.hasBoundedWidth
            ? constraints.maxWidth * trailingShare
            : double.infinity;
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: <Widget>[
            if (icon case final data?) ...<Widget>[
              SystemIcon(
                data,
                size: 20,
                color: iconColor ?? theme.colorScheme.onSurface,
              ),
              const SizedBox(width: OneSpacing.small),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    style ??
                    theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
              ),
            ),
            if (trailing.isNotEmpty) ...<Widget>[
              const SizedBox(width: OneSpacing.small),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < trailing.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: OneSpacing.small),
                      Flexible(child: trailing[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
