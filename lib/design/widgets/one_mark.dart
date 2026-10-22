import 'dart:math' as math;

import 'package:flutter/material.dart';

/// OneWIFI 品牌标（双圆标）：左月牙 + 右实圆，与两端启动图标同一套几何。
///
/// 几何源自 1024 主图：mark 外框 512×320，
/// 左圆 (160,160) 缺口圆 (288,160) 右圆 (352,160)，半径均为 160（局部坐标）。
/// 绘制时标宽 = box × 0.8，标高 = box × 0.5，居中。
final class OneMark extends StatelessWidget {
  const OneMark({this.size = 24, this.color, super.key});

  /// 与 [Icon.size] 同语义的外框边长。
  final double size;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? const Color(0xFFFFFFFF);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OneMarkPainter(ink)),
    );
  }
}

final class _OneMarkPainter extends CustomPainter {
  const _OneMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size box) {
    // 宽高都可能被父级拉伸，按短边定标，保证任何约束下尺寸一致。
    final side = math.min(box.width, box.height);
    final markW = side * 0.8;
    final markH = side * 0.5; // 512:320 比例
    canvas.translate(
      box.width / 2 - markW / 2,
      box.height / 2 - markH / 2,
    );
    canvas.scale(markW / 512);

    final paint = Paint()..color = color;
    final left = Path()
      ..addOval(Rect.fromCircle(center: const Offset(160, 160), radius: 160));
    final cut = Path()
      ..addOval(Rect.fromCircle(center: const Offset(288, 160), radius: 160));
    final right = Path()
      ..addOval(Rect.fromCircle(center: const Offset(352, 160), radius: 160));
    // 先差集出月牙，再并上右圆；显式两步布尔，避免第三段子路径绕向出错。
    final crescent = Path.combine(PathOperation.difference, left, cut);
    final mark = Path.combine(PathOperation.union, crescent, right);
    canvas.drawPath(mark, paint);
  }

  @override
  bool shouldRepaint(_OneMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
