import 'dart:async';

import 'package:flutter/services.dart';

/// PushKit 交给本安装实例的 VoIP 令牌。
///
/// 令牌只标识「哪一次安装」，本身没有任何权限含义；只有被已登录会话登记到
/// 网关之后，服务端才可能向它推送来电。因此它不落盘、不进日志。
final class CallPushToken {
  const CallPushToken({required this.deviceToken, required this.environment});

  final String deviceToken;
  final String environment;

  /// 令牌只有在同时具备合法的十六进制主体和已知环境时才可用：环境决定
  /// 服务端投递到 sandbox 还是 production，猜错会让来电完全不响。
  static CallPushToken? parse(Object? value) {
    if (value is! Map) return null;
    final deviceToken = '${value['device_token'] ?? ''}'.trim().toLowerCase();
    final environment = '${value['environment'] ?? ''}'.trim().toLowerCase();
    if (deviceToken.isEmpty || !RegExp(r'^[0-9a-f]+$').hasMatch(deviceToken)) {
      return null;
    }
    if (environment != 'sandbox' && environment != 'production') return null;
    return CallPushToken(deviceToken: deviceToken, environment: environment);
  }

  @override
  bool operator ==(Object other) =>
      other is CallPushToken &&
      other.deviceToken == deviceToken &&
      other.environment == environment;

  @override
  int get hashCode => Object.hash(deviceToken, environment);
}

abstract interface class CallPushTokens {
  /// 幂等：确保原生 registry 存在，并返回系统当前给出的令牌。
  ///
  /// 系统还没发令牌时返回 null，那一刻只能等 [changes]。之所以要主动读，
  /// 是因为原生先于 Flutter 建 registry：被推送唤醒时令牌往往已经就位，而
  /// 那次事件发生在 Dart 订阅之前。
  Future<CallPushToken?> start();

  Stream<CallPushToken> get changes;
}

final class IosCallPushTokens implements CallPushTokens {
  IosCallPushTokens({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.oneims.onewifi/call_push') {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;
  final StreamController<CallPushToken> _tokenChanges =
      StreamController<CallPushToken>.broadcast();
  CallPushToken? _last;

  @override
  Stream<CallPushToken> get changes => _tokenChanges.stream;

  @override
  Future<CallPushToken?> start() async {
    final token = CallPushToken.parse(
      await _channel.invokeMethod<Object?>('start'),
    );
    // 原生已经把令牌交给过 Dart（start 的返回值就是它），后续事件里同一个
    // 令牌不该再被当成「变化」上报一次。
    if (token != null) _last = token;
    return token;
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'token') return;
    final token = CallPushToken.parse(call.arguments);
    if (token == null || _tokenChanges.isClosed) return;
    // 服务端登记是 upsert，但重复登记没有意义：只把真正变化推给上层。
    if (token.deviceToken == _last?.deviceToken &&
        token.environment == _last?.environment) {
      return;
    }
    _last = token;
    _tokenChanges.add(token);
  }
}