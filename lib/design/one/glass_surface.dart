import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass.dart';

/// 真磨砂玻璃面板：[BackdropFilter] 模糊背后内容 + 半透明填充 + 发丝描边。
///
/// 开销明显高于半透明，**只用于少数高价值面**（首页门面卡、顶栏、悬浮层）；
/// 大量列表卡片请直接用主题里的 Card 玻璃皮。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = Glass.radiusCard,
    this.blur = Glass.blurPanel,
    this.strong = true,
    this.color,
    this.padding,
    this.onTap,
    this.elevate = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final bool strong;

  /// 覆盖默认的 [Glass.fillStrong] / [Glass.fill]。底栏用 [Glass.liquidDockFill]。
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 底栏关掉重投影，避免胶囊底下勒出一道黑影。
  final bool elevate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    return DecoratedBox(
      // 投影要画在裁剪之外，否则会被 ClipRRect 一起裁掉。
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevate ? Glass.shadow(dark, strong: true) : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  color ??
                  (strong
                      ? Glass.fillStrong(theme.colorScheme, dark)
                      : Glass.fill(theme.colorScheme, dark)),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Glass.stroke(theme.colorScheme, dark),
                width: Glass.strokeWidth,
              ),
            ),
            child: onTap == null
                ? content
                : Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: onTap, child: content),
                  ),
          ),
        ),
      ),
    );
  }
}
