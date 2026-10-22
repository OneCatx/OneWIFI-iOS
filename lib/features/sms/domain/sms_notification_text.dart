import 'sms.dart';

/// One visible line: card name, phone tail, verification code.
String smsNotificationText({
  required String content,
  required String sender,
  required String device,
  String? code,
}) {
  final resolved = (code ?? '').trim();
  final name = device.trim();
  final tail = _tail(sender);
  final headline = <String>[
    if (name.isNotEmpty) name,
    if (tail.isNotEmpty) tail,
    if (resolved.isNotEmpty) resolved,
  ].join(' · ');
  if (headline.isNotEmpty) return headline;
  final fallback = content.trim();
  return fallback.isEmpty ? '收到新短信' : fallback;
}

String smsNotificationTextFor(SmsOtpHit hit) => smsNotificationText(
  content: hit.code,
  sender: hit.senderDisplay,
  device: hit.deviceName,
  code: hit.code,
);

String _tail(String sender) {
  final digits = sender.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 4) return digits.substring(digits.length - 4);
  return sender.trim();
}