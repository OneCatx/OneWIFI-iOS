import 'package:flutter/services.dart';

import '../domain/sms.dart';

/// 只有原生系统确认通知已提交，才复制验证码；拒绝授权不复制。
final class NativeSmsOtpSink
    implements SmsOtpDeliverySink, SmsMessageDeliverySink, SmsOtpActivitySink {
  NativeSmsOtpSink({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('com.oneims.onewifi/otp');

  final MethodChannel channel;
  int _generation = 0;

  @override
  Future<void> present(SmsOtpHit hit) async {
    await deliver(hit);
  }

  @override
  Future<bool> deliver(SmsOtpHit hit) async {
    try {
      final delivered = await channel.invokeMethod<bool>(
        'show',
        <String, String>{
          'code': hit.code,
          'sender': hit.senderDisplay,
          'device': hit.deviceName,
        },
      );
      return delivered == true;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> showActivity(SmsOtpHit hit) async {
    final generation = _generation;
    final accepted = await channel.invokeMethod<bool>(
      'showActivity',
      <String, String>{
        'code': hit.code,
        'sender': hit.senderDisplay,
        'device': hit.deviceName,
      },
    );
    return generation == _generation && accepted == true;
  }

  @override
  Future<bool> deliverMessage(SmsRemoteMessage message) async {
    final generation = _generation;
    final delivered = await channel
        .invokeMethod<bool>('showMessage', <String, String>{
          'content': message.content,
          'sender': message.senderDisplay,
          'device': message.deviceName,
        });
    return generation == _generation && delivered == true;
  }

  @override
  Future<void> cancelPending() async {
    _generation += 1;
    await channel.invokeMethod<void>('cancel');
  }
}
