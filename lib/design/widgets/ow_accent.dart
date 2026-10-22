import 'package:flutter/material.dart';

import '../one/glass.dart';

enum MetricTone { green, blue, purple }

/// 铭牌 / 阶段条的语义色。
///
/// [neutral] 是原本的黑白玻璃；其余几色对齐 WEB `glass-frame--tone-green`、
/// `panel-title-icon--teal/purple/blue` 与 `stage-bar.failed`，用来把
/// 「通畅 / 进行中 / 失败 / 信息」从一片黑白里点出来。
/// 产品口径：App 全局不用橙色——WEB 里的 amber 语义（进行中 / 提示）一律落到 blue。
enum PlateTone { neutral, green, teal, purple, blue, red }

/// WEB 主题里的强调色原值（`--green #34d399` 等），深浅两套主题共用色相，
/// 只靠透明度融进玻璃底。
abstract final class OwAccent {
  static const Color green = Color(0xFF34D399);
  static const Color teal = Color(0xFF2DD4BF);

  /// 界面只留青绿两色和白色。旧紫色、蓝色都收进这两色。
  static const Color purple = teal;
  static const Color blue = green;
  static const Color red = Color(0xFFF87171);

  static Color of(PlateTone tone, ColorScheme scheme) => switch (tone) {
    PlateTone.neutral => scheme.onSurface,
    PlateTone.green => green,
    PlateTone.teal => teal,
    PlateTone.purple => purple,
    PlateTone.blue => blue,
    PlateTone.red => red,
  };

  static Color ofMetric(MetricTone tone) => switch (tone) {
    MetricTone.green => green,
    MetricTone.blue => blue,
    MetricTone.purple => purple,
  };

  /// 浅色主题下亮色相文字对比不够，压暗一档再当文字色。
  static Color ink(Color accent, bool dark) => dark
      ? accent
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.38), accent);

  /// 状态牌里那颗小圆点的光：WEB `.overview-badge__dot`
  /// （深色 `0 0 12px rgba(52,211,153,.95)`，浅色 `0 0 8px .45`）。
  /// 「已连接」的亮度全在这颗点上，牌面本身不发光。
  static List<BoxShadow> dotGlow(Color accent, bool dark) => <BoxShadow>[
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.95 : 0.45),
      blurRadius: dark ? 12 : 8,
    ),
  ];

  /// 状态牌牌面的那一点点晕：WEB `.device-card__tag`
  /// `box-shadow: 0 0 16px rgba(52,211,153,.10)`——只是让它别贴死在底上。
  static List<BoxShadow> plateShadow(Color accent) => <BoxShadow>[
    BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 16),
  ];

  /// 选中态：WEB `device-card.is-glow-green`
  /// `0 0 0 1px rgba(52,211,153,.10), 0 0 48px rgba(52,211,153,.045)`。
  /// 一圈 1px 细环加一层几乎看不见的远晕；亮度都在边上，不染底。
  static List<BoxShadow> selectedShadow(Color accent) => <BoxShadow>[
    BoxShadow(color: accent.withValues(alpha: 0.10), spreadRadius: 1),
    BoxShadow(color: accent.withValues(alpha: 0.045), blurRadius: 48),
  ];

  /// 选中态描边：WEB `border-color: rgba(52,211,153,.14)`。Flutter 圆角边框
  /// 四边颜色必须一致，所以左上那两条更亮的内高光不走 border，
  /// 由 [selectedSheen] 与 [SelectedEdgeLight] 补。
  static Border selectedBorder(Color accent, bool dark) => Border.all(
    color: accent.withValues(alpha: dark ? 0.18 : 0.28),
    width: Glass.strokeWidth,
  );

  /// 选中态的边缘高光：WEB `.is-glow-green::before`
  /// `linear-gradient(145deg, rgba(110,231,183,.22) 0%, rgba(52,211,153,.07) 24%,
  /// rgba(255,255,255,.02) 52%, rgba(52,211,153,.05) 100%)`。
  /// 只在左上角边缘擦一笔亮，往中间很快就透明，不是整面染色。
  static Gradient selectedSheen(Color accent, bool dark) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const <double>[0.0, 0.24, 0.52, 1.0],
    colors: <Color>[
      Color.lerp(
        accent,
        Colors.white,
        0.35,
      )!.withValues(alpha: dark ? 0.22 : 0.18),
      accent.withValues(alpha: dark ? 0.07 : 0.06),
      Colors.white.withValues(alpha: dark ? 0.02 : 0.0),
      accent.withValues(alpha: dark ? 0.05 : 0.04),
    ],
  );
}

/// 选中态的内高光：WEB `inset 0 1px 0 rgba(110,231,183,.14)` 与
/// `inset 1px 0 0 rgba(52,211,153,.18)`——贴着上边、左边各一根 1px 亮线，
/// 往另一端渐隐。叠在 [OwAccent.selectedSheen] 之上、正文之下，不占布局。
final class SelectedEdgeLight extends StatelessWidget {
  const SelectedEdgeLight({
    required this.accent,
    required this.radius,
    required this.child,
    super.key,
  });

  final Color accent;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Glass.isDark(Theme.of(context));
    final bright = Color.lerp(accent, Colors.white, 0.4)!;
    final top = bright.withValues(alpha: dark ? 0.30 : 0.36);
    final left = accent.withValues(alpha: dark ? 0.26 : 0.32);
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          left: radius,
          right: radius,
          top: 0,
          height: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[top, top.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: radius,
          bottom: radius,
          width: 1,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[left, left.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
