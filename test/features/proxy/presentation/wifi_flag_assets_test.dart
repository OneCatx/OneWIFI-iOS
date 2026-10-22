import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/proxy/presentation/widgets/wifi_flag_mark.dart';

void main() {
  test('packs the bauhinia Hong Kong flag, not two circles', () {
    final svg = File('assets/flags/hk.svg').readAsStringSync();
    expect(svg.contains('rotate(72'), isTrue);
    expect(svg.contains('r="90"'), isFalse);
    expect(wifiFlagAssetPath('HK'), 'assets/flags/hk.svg');
    expect(wifiFlagFocus('HK').x, 0.56);
    expect(wifiFlagFocus('HK').scale, 0.74);
  });

  test('exposes every packaged flag file', () {
    final dir = Directory('assets/flags');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .toList()
          ..sort();
    expect(files.length, 60);
    expect(files, contains('hk.svg'));
    expect(files, contains('us.svg'));
    expect(wifiFlagAssetPath('UK'), 'assets/flags/gb.svg');
    expect(wifiFlagAssetPath('MO'), isNull);
    expect(WifiFlagWatermark.opacity, 0.44);
  });
}
