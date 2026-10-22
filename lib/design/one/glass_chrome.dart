import 'package:flutter/material.dart';

import 'glass.dart';

/// 应用级渐变底：挂在 `MaterialApp.builder`，让全应用的半透明面都有东西可透。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: Glass.backdrop(theme.colorScheme, dark),
      ),
      child: child,
    );
  }
}

/// 主壳列表底部留白：让最后一张卡停在悬浮 Dock 之上，而不是钻进岛里。
///
/// [AppShell] 开了 `extendBody`，内容会从岛两侧透出来；列表必须自己垫这一段。
/// 高度 = 岛内容 + 底隙 + 手势条 + 一档呼吸，不含左右 [Glass.pageMargin]。
double glassDockScrollPadding(BuildContext context) {
  return Glass.dockHeight +
      Glass.dockBottomGap +
      MediaQuery.viewPaddingOf(context).bottom +
      Glass.space16;
}
