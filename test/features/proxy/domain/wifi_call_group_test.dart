import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';

void main() {
  test('group delay map stamps measured leaves and times out the rest', () {
    const group = WifiCallGroup(
      groupName: 'HK-WIFI Selector',
      countryCode: 'HK',
      countryName: '香港',
      flagEmoji: '🇭🇰',
      now: 'MESL | 香港 家宽 01',
      aliveCount: 2,
      totalCount: 2,
      nodes: <WifiCallNode>[
        WifiCallNode(name: 'MESL | 香港 家宽 01', alive: true),
        WifiCallNode(
          name: '🇭🇰 MESL | 香港 家宽 02',
          alive: true,
          probeName: 'MESL | 香港 家宽 02',
        ),
      ],
    );

    final next = group.withProbedDelays(const <String, WifiDelay>{
      'MESL | 香港 家宽 01': WifiDelay.measured(88),
    });

    expect(next.nodes.first.delayMs, 88);
    expect(next.nodes.first.alive, isTrue);
    expect(next.nodes.last.delayFailed, isTrue);
    expect(next.nodes.last.alive, isFalse);
    expect(next.aliveCount, 1);
  });
}
