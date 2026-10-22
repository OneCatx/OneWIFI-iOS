import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:onewifi_android/design/one/glass.dart';
import 'package:onewifi_android/design/one/ime_visibility.dart';

/// 悬浮胶囊底栏：岛浮在内容之上，左右透出页面。
///
/// 材质对齐家族产品 OneTools / Kyant `LiquidBottomTabs`：均匀磨砂 + 半透明填充
/// + 发丝边。**不要**整岛透镜 matrix、**不要** [Glass.liquidHighlight] 上白下黑——
/// 那两样会在胶囊中间勒出一道黑带。选中格用滑动的液态指示条，格子之间没有竖分割线。
///
/// 内部仍用 [NavigationBar]，保留 M3 无障碍与 `find.byType(NavigationBar)`。
/// [NavigationBar] 自带 SafeArea。岛已经用外层 padding 抬离手势条，必须把底部
/// padding 吃掉，否则岛会被垫高一截、胶囊被拉成长条。
class GlassDock extends StatefulWidget {
  const GlassDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock>
    with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(milliseconds: 480);

  late final AnimationController _slide;
  int _fromIndex = 0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex;
    _slide = AnimationController(vsync: this, duration: _slideDuration)
      ..value = 1;
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    _fromIndex = oldWidget.selectedIndex;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _slide.value = 1;
    } else {
      _slide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    _slide.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold 会把 bottomNavigationBar 垫在输入法上面。岛再留着，就会在键盘和
    // 页面之间多出一块实底胶囊——看起来像「挡了一层」。键盘起来就把岛收掉。
    if (isSoftwareKeyboardVisible(context)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = Glass.isDark(theme);
    final accent = Glass.accent(scheme);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // 页面字号可以小，底栏跟安卓一样用 1.0，避免框是满高、字被缩没。
    const dockHeight = Glass.dockHeight;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Glass.pageMargin,
        0,
        Glass.pageMargin,
        Glass.dockBottomGap + bottomInset,
      ),
      child: Stack(
        children: [
          GlassPanel(
            radius: Glass.radiusDock,
            blur: Glass.blurDock,
            color: Glass.liquidDockFill(scheme, dark),
            elevate: false,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Theme(
                data: theme.copyWith(
                  navigationBarTheme: theme.navigationBarTheme.copyWith(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    indicatorColor: Colors.transparent,
                    overlayColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.pressed)) {
                        return accent.withValues(alpha: 0.10);
                      }
                      return Colors.transparent;
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      final selected = states.contains(WidgetState.selected);
                      return IconThemeData(
                        size: 20,
                        color: selected ? accent : scheme.onSurfaceVariant,
                      );
                    }),
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      final selected = states.contains(WidgetState.selected);
                      return theme.textTheme.labelSmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? accent : scheme.onSurfaceVariant,
                      );
                    }),
                  ),
                ),
                child: SizedBox(
                  height: dockHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedBuilder(
                            animation: _slide,
                            builder: (context, _) {
                              return _DockLiquidIndicator(
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                count: widget.destinations.length,
                                fromIndex: _fromIndex,
                                toIndex: widget.selectedIndex,
                                progress: reduce ? 1 : _slide.value,
                                scheme: scheme,
                                dark: dark,
                              );
                            },
                          ),
                          MediaQuery.withNoTextScaling(
                            child: NavigationBar(
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              indicatorColor: Colors.transparent,
                              height: dockHeight,
                              maintainBottomViewPadding: false,
                              animationDuration: reduce
                                  ? Duration.zero
                                  : _slideDuration,
                              selectedIndex: widget.selectedIndex,
                              onDestinationSelected:
                                  widget.onDestinationSelected,
                              destinations: widget.destinations,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: kGlassDockRimKey,
                painter: DockRimHighlightPainter(
                  radius: Glass.radiusDock,
                  dark: dark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 测试用：液态指示条的盒子。宽高就是当前这一帧的胶囊，用来断言切换时会拉宽。
@visibleForTesting
const Key kGlassDockIndicatorKey = Key('glass-dock-indicator');

/// 测试用：底栏外框高光描边。
@visibleForTesting
const Key kGlassDockRimKey = Key('glass-dock-rim');

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Kyant 指示条的前后沿：去的那边先走，来的那边后收，中途会盖住两格。
@visibleForTesting
({double left, double right}) glassDockTabEdges({
  required double from,
  required double to,
  required double t,
  required int count,
}) {
  final clampedT = t.clamp(0.0, 1.0);
  if (count <= 0) return (left: 0.0, right: 0.0);
  if (from == to) {
    final i = from.clamp(0, (count - 1).toDouble()).toDouble();
    return (left: i, right: i + 1);
  }
  final lead = Curves.easeOutCubic.transform(clampedT);
  final trail = Curves.easeInCubic.transform(clampedT);
  final double left;
  final double right;
  if (to >= from) {
    left = _lerp(from, to, trail);
    right = _lerp(from + 1, to + 1, lead);
  } else {
    left = _lerp(from, to, lead);
    right = _lerp(from + 1, to + 1, trail);
  }
  return (
    left: left.clamp(0.0, count.toDouble()).toDouble(),
    right: right.clamp(0.0, count.toDouble()).toDouble(),
  );
}

class _DockLiquidIndicator extends StatelessWidget {
  const _DockLiquidIndicator({
    required this.width,
    required this.height,
    required this.count,
    required this.fromIndex,
    required this.toIndex,
    required this.progress,
    required this.scheme,
    required this.dark,
  });

  final double width;
  final double height;
  final int count;
  final int fromIndex;
  final int toIndex;
  final double progress;
  final ColorScheme scheme;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (count <= 0 || width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }
    final travel = math.sin(math.pi * progress.clamp(0.0, 1.0));
    final edges = glassDockTabEdges(
      from: fromIndex.toDouble(),
      to: toIndex.toDouble(),
      t: progress,
      count: count,
    );
    const pad = Glass.dockTabInset;
    final inner = math.max(0.0, width - pad * 2);
    final tabW = inner / count;
    final left = pad + edges.left * tabW;
    final right = pad + edges.right * tabW;
    final indicatorH = math.min(
      Glass.dockIndicatorHeight,
      math.max(0.0, height - pad * 2),
    );
    final top = (height - indicatorH) / 2;
    final radius = indicatorH / 2;
    final restFill = Glass.liquidDockIndicatorFill(scheme, dark);
    final travelFill = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.10);
    final fill = Color.lerp(restFill, travelFill, travel)!;
    final boxWidth = math.max(0.0, right - left);
    return Stack(
      children: [
        Positioned(
          key: kGlassDockIndicatorKey,
          left: left,
          top: top,
          width: boxWidth,
          height: indicatorH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: CustomPaint(
                painter: _GlassRRectHighlightPainter(
                  radius: radius,
                  dark: dark,
                  opacity: 0.85 * travel,
                  strokeWidth: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 底栏外框高光：只描边，不往填充里铺上白下黑。
class DockRimHighlightPainter extends CustomPainter {
  const DockRimHighlightPainter({required this.radius, required this.dark});

  final double radius;
  final bool dark;

  static const double _strokeWidth = 1.25;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(_strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const <Color>[
                Color(0x8CFFFFFF),
                Color(0x1AFFFFFF),
                Color(0x47FFFFFF),
              ]
            : const <Color>[
                Color(0xB8FFFFFF),
                Color(0x2EFFFFFF),
                Color(0x52FFFFFF),
              ],
        stops: const <double>[0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant DockRimHighlightPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.dark != dark;
  }
}

/// 液态玻璃指示条的中性边缘高光。只画描边，不往中间铺渐变，
/// 避免底栏在黑白主题里出现彩虹色散。
class _GlassRRectHighlightPainter extends CustomPainter {
  const _GlassRRectHighlightPainter({
    required this.radius,
    required this.dark,
    required this.opacity,
    required this.strokeWidth,
  });

  final double radius;
  final bool dark;
  final double opacity;
  final double strokeWidth;

  static const List<Color> _darkHighlight = <Color>[
    Color(0x3DFFFFFF),
    Color(0x0FFFFFFF),
    Color(0x24FFFFFF),
    Color(0x0AFFFFFF),
    Color(0x3DFFFFFF),
  ];

  static const List<Color> _lightHighlight = <Color>[
    Color(0x66FFFFFF),
    Color(0x14FFFFFF),
    Color(0x14000000),
    Color(0x0AFFFFFF),
    Color(0x66FFFFFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [
          for (final color in (dark ? _darkHighlight : _lightHighlight))
            color.withValues(alpha: color.a * opacity),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRRectHighlightPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.dark != dark ||
        oldDelegate.opacity != opacity ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
