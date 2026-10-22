import 'package:flutter/material.dart';

import '../one/glass.dart' as one;
import 'ow_accent.dart';

/// High-value frosted panel. Keep this off list rows.
final class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(one.Glass.padCard),
    this.radius = one.Glass.radiusCard,
    this.blur = one.Glass.blurPanel,
    this.strong = true,
    this.color,
    this.onTap,
    this.elevate = true,
    super.key,
  });

  final Widget child;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final bool strong;
  final Color? color;
  final VoidCallback? onTap;
  final bool elevate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: one.GlassPanel(
        radius: radius,
        blur: blur,
        strong: strong,
        color: color,
        padding: padding,
        onTap: onTap,
        elevate: elevate,
        child: child,
      ),
    );
  }
}

/// List/container chrome: translucent fill + hairline, no BackdropFilter.
///
/// 给 [selectedAccent] 时走 WEB `device-card.is-glow-green` 的选中：底不变，
/// 边变该色、左上两边更亮、边缘擦一笔高光、外面一圈 1px 细环加极淡远晕。
final class GlassListCard extends StatelessWidget {
  const GlassListCard({
    required this.child,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(one.Glass.padCard),
    this.onTap,
    this.selectedAccent,
    super.key,
  });

  final Widget child;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? selectedAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = one.Glass.isDark(theme);
    final radius = BorderRadius.circular(one.Glass.radiusCard);
    final body = Padding(padding: padding, child: child);
    final accent = selectedAccent;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: one.Glass.fillStrong(theme.colorScheme, dark),
          borderRadius: radius,
          border: accent == null
              ? Border.all(
                  color: one.Glass.stroke(theme.colorScheme, dark),
                  width: one.Glass.strokeWidth,
                )
              : OwAccent.selectedBorder(accent, dark),
          boxShadow: accent == null
              ? one.Glass.shadow(dark, strong: true)
              : <BoxShadow>[
                  ...OwAccent.selectedShadow(accent),
                  ...one.Glass.shadow(dark, strong: true),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: accent == null
                  ? null
                  : OwAccent.selectedSheen(accent, dark),
            ),
            child: accent == null
                ? (onTap == null ? body : InkWell(onTap: onTap, child: body))
                : SelectedEdgeLight(
                    accent: accent,
                    radius: one.Glass.radiusCard,
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
