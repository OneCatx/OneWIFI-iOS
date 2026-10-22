import 'package:flutter/services.dart';

/// 原生激活库读失败。不得折成「未激活」。
class LicenseReadException implements Exception {
  LicenseReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 原生激活通道 `onewifi/activation`。token 只在 Kotlin 侧。
class ActivationChannel {
  const ActivationChannel._();

  static const MethodChannel _method = MethodChannel('onewifi/activation');

  static Future<ActivationStatus?> tryGetState() async {
    try {
      final raw = await _method.invokeMapMethod<String, dynamic>('getState');
      if (raw == null) return ActivationStatus.preview;
      return ActivationStatus.fromMap(raw);
    } on PlatformException catch (e) {
      throw LicenseReadException(e.message ?? '无法读取激活状态');
    } on MissingPluginException {
      throw LicenseReadException('当前环境没有激活通道');
    }
  }

  static Future<ActivationWriteResult> activate(String code) =>
      _write('activate', {'code': code});

  static Future<ActivationWriteResult> deactivate() => _write('deactivate');

  static Future<ActivationWriteResult> _write(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final raw = await _method.invokeMapMethod<String, dynamic>(method, args);
      if (raw == null) {
        return const ActivationWriteResult(ok: false, message: '激活通道无响应');
      }
      return ActivationWriteResult.fromMap(raw);
    } on PlatformException catch (e) {
      return ActivationWriteResult(ok: false, message: e.message ?? '激活失败');
    } on MissingPluginException {
      return const ActivationWriteResult(
        ok: false,
        message: '当前环境没有激活通道',
        unavailable: true,
      );
    }
  }
}

class ActivationStatus {
  const ActivationStatus({
    required this.activated,
    this.code,
    this.membershipBadge,
    this.encrypted = false,
  });

  final bool activated;
  final String? code;
  final String? membershipBadge;
  final bool encrypted;

  static const preview = ActivationStatus(activated: false);

  factory ActivationStatus.fromMap(Map<String, dynamic> m) => ActivationStatus(
    activated: m['activated'] == true,
    code: m['code'] as String?,
    membershipBadge: m['membershipBadge'] as String?,
    encrypted: m['encrypted'] == true,
  );
}

class ActivationWriteResult {
  const ActivationWriteResult({
    required this.ok,
    this.message,
    this.unavailable = false,
    this.activated = false,
    this.code,
  });

  final bool ok;
  final String? message;
  final bool unavailable;
  final bool activated;
  final String? code;

  factory ActivationWriteResult.fromMap(Map<String, dynamic> m) =>
      ActivationWriteResult(
        ok: m['ok'] == true,
        message: m['message'] as String?,
        activated: m['activated'] == true,
        code: m['code'] as String?,
      );
}
