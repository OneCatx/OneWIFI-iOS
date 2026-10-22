import 'package:flutter/material.dart';

import '../one/glass.dart';
import 'ow_accent.dart';

/// WEB `glass-frame glass-frame--compact`：框里的小瓷片（软标签格、策略字段、
/// eSIM 项都是它）。给 [tone] 时描边与底透出语义色；[selected] 走 WEB
/// `glass-frame--selectable.is-glow-green` 的选中变色（底透绿、边变绿、
/// 1px 细环），不发大光；[onTap] 非空时整片可点。
final class GlassTile extends StatelessWidget {
  const GlassTile({
    required this.child,
    this.tone,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Glass.space12 + Glass.space2,
      vertical: Glass.space12,
    ),
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final PlateTone? tone;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final scheme = theme.colorScheme;
    final accent = tone == null || tone == PlateTone.neutral
        ? null
        : OwAccent.of(tone!, scheme);
    final radius = BorderRadius.circular(Glass.radiusTile);
    final body = Padding(padding: padding, child: child);
    final glow = selected ? (accent ?? OwAccent.green) : null;
    final Color fill;
    final BoxBorder border;
    if (glow != null) {
      // 选中不染底：底还是普通玻璃，亮度全在边缘高光与细环上。
      fill = Glass.fill(scheme, dark);
      border = OwAccent.selectedBorder(glow, dark);
    } else if (accent != null) {
      fill = accent.withValues(alpha: dark ? 0.12 : 0.09);
      border = Border.all(
        color: accent.withValues(alpha: dark ? 0.42 : 0.34),
        width: Glass.strokeWidth,
      );
    } else {
      fill = Glass.fill(scheme, dark);
      border = Border.all(
        color: Glass.stroke(scheme, dark),
        width: Glass.strokeWidth,
      );
    }
    return Semantics(
      container: semanticLabel != null,
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: border,
          boxShadow: glow == null
              ? Glass.shadow(dark)
              : <BoxShadow>[
                  ...OwAccent.selectedShadow(glow),
                  ...Glass.shadow(dark),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: glow == null
                  ? null
                  : OwAccent.selectedSheen(glow, dark),
            ),
            child: glow == null
                ? (onTap == null ? body : InkWell(onTap: onTap, child: body))
                : SelectedEdgeLight(
                    accent: glow,
                    radius: Glass.radiusTile,
                    child: onTap == null
                        ? body
                        : InkWell(onTap: onTap, child: body),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 细进度条。给 [tone] 时走语义色（WEB `.usage-bar--green/blue/purple`），
/// 不给保持黑白。
final class ThinProgress extends StatelessWidget {
  const ThinProgress({required this.value, this.tone, super.key});

  final double value;
  final PlateTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final clamped = value.isFinite ? value.clamp(0, 100) / 100 : 0.0;
    final accent = tone == null || tone == PlateTone.neutral
        ? null
        : OwAccent.of(tone!, theme.colorScheme);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: clamped,
          backgroundColor: theme.colorScheme.outlineVariant.withValues(
            alpha: 0.35,
          ),
          color:
              accent?.withValues(alpha: dark ? 0.92 : 0.86) ??
              theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
