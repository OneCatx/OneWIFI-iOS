import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/settings/domain/license_code.dart';

void main() {
  test('accepts four groups and optional PRO/ULTRA suffix', () {
    expect(
      LicenseCode.validate('ab12-cd34-ef56-gh78').normalized,
      'AB12-CD34-EF56-GH78',
    );
    expect(
      LicenseCode.validate('AB12CD34EF56GH78ULTRA').normalized,
      'AB12-CD34-EF56-GH78-ULTRA',
    );
  });

  test('rejects empty and malformed codes', () {
    expect(LicenseCode.validate('').error, CodeError.empty);
    expect(LicenseCode.validate('ABCD').error, CodeError.format);
    expect(LicenseCode.localError('ABCD'), '格式应为 XXXX-XXXX-XXXX-XXXX');
    expect(LicenseCode.localError(''), isNull);
  });
}
