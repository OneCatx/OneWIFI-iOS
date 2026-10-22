import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/design/widgets/ow_accent.dart';
import 'package:onewifi_android/features/proxy/domain/wifi_call_group.dart';
import 'package:onewifi_android/features/proxy/presentation/widgets/wifi_node_status.dart';

void main() {
  test('badge shows ms, 测速中, em dash, and 超时 only after a real fail', () {
    const live = WifiCallNode(name: 'n', alive: true, delayMs: 80);
    const pending = WifiCallNode(name: 'n', alive: true);
    const unknown = WifiCallNode(name: 'n', alive: true, delayProbed: true);
    const timedOut = WifiCallNode(
      name: 'n',
      alive: false,
      delayProbed: true,
      delayFailed: true,
    );
    const catalogDead = WifiCallNode(name: 'n', alive: false);

    expect(wifiNodeBadge(live), '80ms');
    expect(wifiNodeBadge(pending), '—');
    expect(wifiNodeBadge(pending, probing: true), '测速中');
    expect(wifiNodeBadge(unknown), '—');
    expect(wifiNodeShowsPlate(unknown), isFalse);
    expect(wifiNodeShowsPlate(pending), isFalse);
    expect(wifiNodeShowsPlate(pending, probing: true), isTrue);
    expect(wifiNodeShowsPlate(live), isTrue);
    expect(wifiNodeShowsPlate(timedOut), isTrue);
    expect(wifiNodeBadge(timedOut), '超时');
    expect(wifiNodeBadge(catalogDead), '超时');
    expect(wifiNodeTone(unknown), PlateTone.neutral);
    expect(wifiNodeTone(timedOut), PlateTone.red);
  });

  test('unknown probe keeps a previous millisecond reading', () {
    const node = WifiCallNode(name: 'n', alive: true, delayMs: 80);
    final next = node.withProbedDelay(const WifiDelay.unknown());
    expect(wifiNodeBadge(next), '80ms');
    expect(next.delayFailed, isFalse);
    expect(next.alive, isTrue);
  });
}
