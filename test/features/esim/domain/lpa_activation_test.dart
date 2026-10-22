import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/esim/domain/lpa_activation.dart';

void main() {
  test('parses GSMA codes with and without the LPA prefix', () {
    final prefixed = parseLpaActivationCode(
      'LPA:1\$rsp.example.test\$matching-id\$confirm-9',
    );
    expect(prefixed.smdp, 'rsp.example.test');
    expect(prefixed.matchingId, 'matching-id');
    expect(prefixed.confirmationCode, 'confirm-9');

    final bare = parseLpaActivationCode('1\$smdp.carrier.test\$match');
    expect(bare.smdp, 'smdp.carrier.test');
    expect(bare.matchingId, 'match');
    expect(bare.confirmationCode, isEmpty);
  });

  test('treats a host-only paste as SM-DP+ and strips https URLs', () {
    expect(parseLpaActivationCode('rsp.only.test').smdp, 'rsp.only.test');
    expect(
      parseLpaActivationCode('https://rsp.example.test/path').smdp,
      'rsp.example.test',
    );
    expect(parseLpaActivationCode('').hasSmdp, isFalse);
  });
}
