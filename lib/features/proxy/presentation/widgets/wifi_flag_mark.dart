import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 左 1/3 实黑，向右淡出国旗；旗面落在右 2/3，相对 0.1.8 的铺满再缩 30%，对齐 logo。
final class WifiFlagWatermark extends StatelessWidget {
  const WifiFlagWatermark({
    required this.countryCode,
    required this.flagEmoji,
    super.key,
  });

  final String countryCode;
  final String flagEmoji;

  static const double _rightShare = 2 / 3;
  static const double _shrink = 0.70;
  static const double opacity = 0.44;

  @override
  Widget build(BuildContext context) {
    final focus = wifiFlagFocus(countryCode);
    final asset = wifiFlagAssetPath(countryCode);
    return Semantics(
      label: flagEmoji,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
              return const SizedBox.shrink();
            }
            final zoneWidth = constraints.maxWidth * _rightShare;
            final flagWidth = constraints.maxWidth * 2.20 * _shrink;
            final flagHeight = math.max(
              constraints.maxHeight * 3.60 * _shrink,
              flagWidth * 480 / 640,
            );
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.97)),
                Positioned(
                  width: flagWidth,
                  height: flagHeight,
                  right: -(flagWidth - zoneWidth) / 2,
                  top: constraints.maxHeight / 2 - flagHeight / 2,
                  child: Transform.rotate(
                    angle: -12 * math.pi / 180,
                    alignment: Alignment(focus.x * 2 - 1, 0),
                    child: Transform.scale(
                      scale: focus.scale,
                      alignment: Alignment(focus.x * 2 - 1, focus.y * 2 - 1),
                      child: Opacity(
                        opacity: opacity,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.matrix(
                            _kFlagColorMatrix,
                          ),
                          child: asset == null
                              ? const SizedBox.expand()
                              : SvgPicture.asset(
                                  asset,
                                  fit: BoxFit.cover,
                                  alignment: Alignment(
                                    focus.x * 2 - 1,
                                    focus.y * 2 - 1,
                                  ),
                                  placeholderBuilder: (_) =>
                                      const SizedBox.expand(),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(child: _LeftThirdBlend()),
              ],
            );
          },
        ),
      ),
    );
  }
}

final class WifiFlagFocus {
  const WifiFlagFocus({required this.x, required this.y, required this.scale});

  final double x;
  final double y;
  final double scale;
}

WifiFlagFocus wifiFlagFocus(String countryCode) {
  final iso = wifiFlagIso(countryCode);
  return _kFlagFocus[iso] ?? const WifiFlagFocus(x: 0.62, y: 0.50, scale: 0.70);
}

String wifiFlagIso(String countryCode) {
  final upper = countryCode.trim().toUpperCase();
  if (upper == 'UK') return 'GB';
  return upper;
}

String? wifiFlagAssetPath(String countryCode) {
  final iso = wifiFlagIso(countryCode).toLowerCase();
  if (!_kPackagedFlagFiles.contains(iso)) return null;
  return 'assets/flags/$iso.svg';
}

const List<double> _kFlagColorMatrix = <double>[
  0.999162,
  -0.09009,
  -0.009072,
  0,
  0,
  -0.026838,
  0.93591,
  -0.009072,
  0,
  0,
  -0.026838,
  -0.09009,
  1.016928,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const Map<String, WifiFlagFocus> _kFlagFocus = <String, WifiFlagFocus>{
  'HK': WifiFlagFocus(x: 0.56, y: 0.42, scale: 0.74),
  'GB': WifiFlagFocus(x: 0.50, y: 0.50, scale: 0.74),
  'US': WifiFlagFocus(x: 0.34, y: 0.34, scale: 0.74),
  'NZ': WifiFlagFocus(x: 0.72, y: 0.48, scale: 0.74),
  'DE': WifiFlagFocus(x: 0.50, y: 0.46, scale: 0.70),
  'JP': WifiFlagFocus(x: 0.58, y: 0.50, scale: 0.70),
  'SG': WifiFlagFocus(x: 0.50, y: 0.50, scale: 0.70),
  'TW': WifiFlagFocus(x: 0.48, y: 0.50, scale: 0.70),
  'KR': WifiFlagFocus(x: 0.52, y: 0.50, scale: 0.70),
};

const Set<String> _kPackagedFlagFiles = <String>{
  'ae',
  'ar',
  'at',
  'au',
  'bd',
  'be',
  'br',
  'ca',
  'ch',
  'cl',
  'cn',
  'co',
  'cz',
  'de',
  'dk',
  'eg',
  'es',
  'fi',
  'fr',
  'gb',
  'gr',
  'hk',
  'hu',
  'id',
  'ie',
  'il',
  'in',
  'it',
  'jp',
  'ke',
  'kh',
  'kr',
  'la',
  'lk',
  'ma',
  'mm',
  'mx',
  'my',
  'ng',
  'nl',
  'no',
  'np',
  'nz',
  'pe',
  'ph',
  'pk',
  'pl',
  'pt',
  'ro',
  'ru',
  'sa',
  'se',
  'sg',
  'th',
  'tr',
  'tw',
  'ua',
  'us',
  'vn',
  'za',
};

final class _LeftThirdBlend extends StatelessWidget {
  const _LeftThirdBlend();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color.fromRGBO(0, 0, 0, 1.00),
            Color.fromRGBO(0, 0, 0, 0.98),
            Color.fromRGBO(0, 0, 0, 0.42),
            Color.fromRGBO(0, 0, 0, 0.08),
            Color.fromRGBO(0, 0, 0, 0.00),
          ],
          stops: <double>[0.00, 0.33, 0.52, 0.78, 1.00],
        ),
      ),
    );
  }
}
