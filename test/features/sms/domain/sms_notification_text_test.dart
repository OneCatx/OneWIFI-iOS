import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/domain/sms_notification_text.dart';

void main() {
  test('otp line is card name, phone tail, and code', () {
    expect(
      smsNotificationText(
        content: '您的验证码是 123456，5分钟内有效',
        sender: '+86 13800138000',
        device: '旅行卡',
        code: '123456',
      ),
      '旅行卡 · 8000 · 123456',
    );
  });

  test('missing card name still keeps tail and code', () {
    expect(
      smsNotificationText(
        content: 'code 654321',
        sender: '10086',
        device: '  ',
        code: '654321',
      ),
      '0086 · 654321',
    );
  });

  test('non-otp falls back to the message body', () {
    expect(
      smsNotificationText(content: '  普通短信  ', sender: '', device: ''),
      '普通短信',
    );
  });

  test('local otp hit uses the same line', () {
    expect(
      smsNotificationTextFor(
        const SmsOtpHit(
          code: '123456',
          senderDisplay: '•••• 8000',
          deviceName: '旅行卡',
        ),
      ),
      '旅行卡 · 8000 · 123456',
    );
  });
}