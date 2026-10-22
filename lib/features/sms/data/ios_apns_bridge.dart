import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统通知权限。灵动岛（实时活动）与横幅通知是两套独立开关，
/// 能显示灵动岛不代表系统允许展示通知横幅。
enum IosPushAuthorization {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral;

  static IosPushAuthorization parse(Object? raw) => switch ('$raw') {
    'authorized' => IosPushAuthorization.authorized,
    'provisional' => IosPushAuthorization.provisional,
    'ephemeral' => IosPushAuthorization.ephemeral,
    'denied' => IosPushAuthorization.denied,
    _ => IosPushAuthorization.notDetermined,
  };

  bool get canPresent => switch (this) {
    IosPushAuthorization.authorized ||
    IosPushAuthorization.provisional ||
    IosPushAuthorization.ephemeral => true,
    _ => false,
  };
}

/// 原生推送事实：地址是否登记成功、系统是否允许展示、登记失败原因。
/// `pushToStartToken` 是 Live Activity 的启动令牌，与 `deviceToken` 属于
/// 两个独立的令牌空间：前者让服务器能在后台直接创建灵动岛，后者只发横幅。
final class IosApnsStatus {
  const IosApnsStatus({
    this.deviceToken = '',
    this.environment = '',
    this.pushToStartToken = '',
    this.authorization = IosPushAuthorization.notDetermined,
    this.alertsEnabled = false,
    this.registrationError = '',
  });

  static const IosApnsStatus empty = IosApnsStatus();

  final String deviceToken;
  final String environment;
  final String pushToStartToken;
  final IosPushAuthorization authorization;
  final bool alertsEnabled;
  final String registrationError;

  bool get registered => deviceToken.isNotEmpty && environment.isNotEmpty;

  /// 只有地址已登记且系统允许展示，后台横幅才可能出现在锁屏/通知中心。
  bool get canPresentAlerts => registered && authorization.canPresent;

  IosApnsStatus merge(Object? value) {
    if (value is! Map) return this;
    final token = '${value['device_token'] ?? ''}'.trim().toLowerCase();
    final environment = '${value['environment'] ?? ''}'.trim().toLowerCase();
    final pushToStart = '${value['push_to_start_token'] ?? ''}'
        .trim()
        .toLowerCase();
    return IosApnsStatus(
      deviceToken: RegExp(r'^[0-9a-f]{64}$').hasMatch(token)
          ? token
          : deviceToken,
      environment: environment == 'sandbox' || environment == 'production'
          ? environment
          : this.environment,
      // 空值不覆盖：旧安装包没有该字段，不能让一次上报抹掉已登记的令牌。
      pushToStartToken: _hexToken.hasMatch(pushToStart)
          ? pushToStart
          : pushToStartToken,
      authorization: value.containsKey('authorization')
          ? IosPushAuthorization.parse(value['authorization'])
          : authorization,
      alertsEnabled: value.containsKey('alerts_enabled')
          ? value['alerts_enabled'] == true
          : alertsEnabled,
      registrationError: value.containsKey('registration_error')
          ? '${value['registration_error'] ?? ''}'.trim()
          : registrationError,
    );
  }
}

final RegExp _hexToken = RegExp(r'^(?:[0-9a-f]{2})+$');

final class IosApnsEvent {
  const IosApnsEvent({
    required this.smsId,
    required this.content,
    required this.number,
    required this.deviceLabel,
    required this.systemPresented,
  });

  final int smsId;
  final String content;
  final String number;
  final String deviceLabel;
  final bool systemPresented;

  static IosApnsEvent? parse(Object? value) {
    if (value is! Map) return null;
    final smsId = value['sms_id'];
    final id = smsId is int ? smsId : int.tryParse('$smsId');
    final content = '${value['content'] ?? ''}'.trim();
    if (id == null || id <= 0 || content.isEmpty) return null;
    return IosApnsEvent(
      smsId: id,
      content: content,
      number: '${value['number'] ?? ''}'.trim(),
      deviceLabel: '${value['device_label'] ?? ''}'.trim(),
      systemPresented: value['system_presented'] == true,
    );
  }
}

final class IosApnsBridge {
  IosApnsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.oneims.onewifi/apns') {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;
  final ValueNotifier<IosApnsStatus> _status = ValueNotifier<IosApnsStatus>(
    IosApnsStatus.empty,
  );
  final StreamController<IosApnsEvent> _events =
      StreamController<IosApnsEvent>.broadcast();
  final StreamController<void> _tokens = StreamController<void>.broadcast();
  bool _disposed = false;

  Stream<IosApnsEvent> get events => _events.stream;
  Stream<void> get tokenChanges => _tokens.stream;
  ValueListenable<IosApnsStatus> get status => _status;
  String get deviceToken => _status.value.deviceToken;
  String get environment => _status.value.environment;

  /// 服务器创建灵动岛所需的启动令牌，与 deviceToken 是两个独立空间。
  String get pushToStartToken => _status.value.pushToStartToken;

  Future<void> start() async {
    _mergeStatus(await _channel.invokeMethod<Object?>('register'));
    _takeEvents(await _channel.invokeMethod<Object?>('drain'));
  }

  Future<void> refresh() async {
    _mergeStatus(await _channel.invokeMethod<Object?>('state'));
    _takeEvents(await _channel.invokeMethod<Object?>('drain'));
  }

  /// 读取系统通知授权。设置页进入时调用一次，失败静默。
  Future<void> refreshAuthorization() async {
    try {
      _mergeStatus(await _channel.invokeMethod<Object?>('notificationState'));
    } on MissingPluginException {
      // 非 iOS 宿主或旧安装包没有该通道方法。
    } on PlatformException {
      // 权限查询失败不影响配对与 SSE。
    }
  }

  /// 弹出系统权限请求；授权后立即重新登记推送地址。
  Future<void> requestAuthorization() async {
    _mergeStatus(
      await _channel.invokeMethod<Object?>('requestNotificationAuthorization'),
    );
  }

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'token':
        _mergeStatus(call.arguments);
        break;
      case 'registrationError':
        _mergeStatus(call.arguments);
        break;
      case 'notification':
        final event = IosApnsEvent.parse(call.arguments);
        if (event != null) _events.add(event);
        break;
    }
  }

  void _mergeStatus(Object? value) {
    if (_disposed) return;
    final before = _status.value;
    final after = before.merge(value);
    if (after.deviceToken == before.deviceToken &&
        after.environment == before.environment &&
        after.pushToStartToken == before.pushToStartToken &&
        after.authorization == before.authorization &&
        after.alertsEnabled == before.alertsEnabled &&
        after.registrationError == before.registrationError) {
      return;
    }
    _status.value = after;
    // 启动令牌变化也要重新登记，否则服务器会继续向已失效的令牌发灵动岛。
    if (after.deviceToken != before.deviceToken ||
        after.environment != before.environment ||
        after.pushToStartToken != before.pushToStartToken) {
      _tokens.add(null);
    }
  }

  void _takeEvents(Object? value) {
    if (value is! List) return;
    for (final item in value) {
      final event = IosApnsEvent.parse(item);
      if (event != null) _events.add(event);
    }
  }

  Future<void> dispose() async {
    // SmsController 与 app 依赖都可能释放同一实例，重复释放必须是空操作。
    if (_disposed) return;
    _disposed = true;
    await _events.close();
    await _tokens.close();
    _status.dispose();
  }
}
