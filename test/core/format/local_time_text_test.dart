import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/format/local_time_text.dart';

void main() {
  test('formatLocalMinute renders local time with zero padding', () {
    final value = DateTime(2026, 1, 5, 7, 3, 9);
    expect(formatLocalMinute(value), '2026-01-05 07:03');
  });

  test('formatLocalSecond appends zero-padded seconds', () {
    final value = DateTime(2026, 12, 31, 23, 59, 4);
    expect(formatLocalSecond(value), '2026-12-31 23:59:04');
  });

  test('utc input is converted to local time before formatting', () {
    final utc = DateTime.utc(2026, 6, 15, 12, 30, 45);
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final expectedMinute =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
    expect(formatLocalMinute(utc), expectedMinute);
    expect(formatLocalSecond(utc), '$expectedMinute:${two(local.second)}');
  });
}
