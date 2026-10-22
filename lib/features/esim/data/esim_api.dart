import 'dart:convert';

import '../../../core/config/gateway_api.dart';
import '../../../core/http/http_transport.dart';
import '../../../core/http/json_shape.dart';
import '../../../core/http/sse_decoder.dart';
import '../../../core/security/redaction.dart';
import '../domain/card_policy.dart';
import '../domain/esim.dart';
import '../domain/euicc_hardware.dart';
import 'esim_notification_dto.dart';

part 'esim_dto.dart';

final class EsimApi {
  const EsimApi(this._transport);

  static const Duration _switchTimeout = Duration(minutes: 2);
  final HttpTransport _transport;

  /// eUICC 总览（硅片身份 + 缓存的 profile 清单）。走网关缓存的 `/esim`
  /// （不带 refresh，不碰 UIM），与 WEB `getEsimOverview` 同一契约：
  /// `{data:{chipInfo:{eids,firmware}|null, profiles: groups}}`。
  Future<EsimOverviewDto> fetchOverview(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.deviceEsim,
      pathParameters: <String, String>{'id': deviceId},
      cancellation: cancellation,
    );
    final envelope = _shape.map(data);
    final root = envelope['data'] is Map<Object?, Object?>
        ? envelope['data'] as Map<Object?, Object?>
        : envelope;
    return EsimOverviewDto(
      hardware: _parseHardware(root),
      profiles: _parseCachedGroups(root['profiles']),
    );
  }

  Future<EsimInventoryDto> fetchProfiles(
    String deviceId, {
    required bool refresh,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.deviceEsimProfiles,
      pathParameters: <String, String>{'id': deviceId},
      queryParameters: <String, String?>{'refresh': refresh ? '1' : null},
      cancellation: cancellation,
    );
    return _parseInventory(data);
  }

  Future<EsimSwitchResult> switchProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    if (target is! _EsimSwitchTarget) {
      throw StateError('Invalid eSIM switch target.');
    }
    final body = <String, String>{'iccid': target._iccid};
    if (target._aidHex.isNotEmpty) body['aid_hex'] = target._aidHex;
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.deviceEsimSwitch,
      pathParameters: <String, String>{'id': deviceId},
      body: body,
      timeout: _switchTimeout,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    final status = switch (_shape.string(map['status'])) {
      'switched' => EsimSwitchStatus.switched,
      'already_active' => EsimSwitchStatus.alreadyActive,
      _ => throw const EsimDtoException(),
    };
    if (_shape.string(map['iccid']) != target._iccid ||
        map['verified'] != true) {
      throw const EsimDtoException();
    }
    return EsimSwitchResult(status: status, verified: true);
  }

  Future<void> renameProfile(
    String deviceId,
    EsimSwitchTarget target, {
    required String name,
    RequestCancellation? cancellation,
  }) async {
    final nickname = name.trim();
    if (nickname.isEmpty) throw const EsimDtoException();
    final data = await _transport.sendJson(
      method: 'PATCH',
      routeTemplate: GatewayApi.deviceEsimProfile,
      pathParameters: <String, String>{
        'id': deviceId,
        'iccid': iccidOf(target),
      },
      body: <String, String>{
        'name': nickname,
        if (aidHexOf(target).isNotEmpty) 'aid_hex': aidHexOf(target),
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    if (_shape.string(map['status']) != 'renamed') {
      throw const EsimDtoException();
    }
  }

  Future<void> disableProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final body = <String, String>{'iccid': iccidOf(target)};
    if (aidHexOf(target).isNotEmpty) body['aid_hex'] = aidHexOf(target);
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.deviceEsimDisable,
      pathParameters: <String, String>{'id': deviceId},
      body: body,
      timeout: _switchTimeout,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    if (_shape.string(map['status']) != 'disabled') {
      throw const EsimDtoException();
    }
  }

  Future<void> deleteProfile(
    String deviceId,
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.deviceEsimProfile,
      pathParameters: <String, String>{
        'id': deviceId,
        'iccid': iccidOf(target),
      },
      queryParameters: <String, String?>{
        'aid_hex': aidHexOf(target).isEmpty ? null : aidHexOf(target),
      },
      timeout: _switchTimeout,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    if (_shape.string(map['status']) != 'deleted') {
      throw const EsimDtoException();
    }
  }

  static String iccidOf(EsimSwitchTarget target) {
    if (target is! _EsimSwitchTarget) {
      throw StateError('Invalid eSIM switch target.');
    }
    return target._iccid;
  }

  static String aidHexOf(EsimSwitchTarget target) {
    if (target is! _EsimSwitchTarget) {
      throw StateError('Invalid eSIM switch target.');
    }
    return target._aidHex;
  }

  Future<CardPolicy> fetchPolicy(
    EsimSwitchTarget target, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.cardPolicy,
      pathParameters: <String, String>{'iccid': iccidOf(target)},
      cancellation: cancellation,
    );
    return _parsePolicy(data);
  }

  Future<CardPolicy> savePolicy(
    EsimSwitchTarget target, {
    required String apn,
    required CardIpVersion ipVersion,
    bool? networkEnabled,
    bool? vowifiEnabled,
    bool? airplaneEnabled,
    String? mbnProfile,
    CardVoicePath? voicePath,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.cardPolicy,
      pathParameters: <String, String>{'iccid': iccidOf(target)},
      body: <String, Object?>{
        'apn': apn,
        'ip_version': ipVersion.apiValue,
        'network_enabled': ?networkEnabled,
        'vowifi_enabled': ?vowifiEnabled,
        'airplane_enabled': ?airplaneEnabled,
        'mbn_profile': ?mbnProfile,
        'voice_path': ?voicePath?.apiValue,
      },
      cancellation: cancellation,
    );
    return _parsePolicy(data);
  }

  Future<void> downloadProfile(
    String deviceId, {
    required String smdp,
    String matchingId = '',
    String confirmationCode = '',
    String aidHex = '',
    void Function(EsimDownloadProgress progress)? onProgress,
    RequestCancellation? cancellation,
  }) async {
    var done = false;
    String? errorMessage;
    await _transport.sendSse(
      method: 'POST',
      routeTemplate: GatewayApi.deviceEsimDownload,
      pathParameters: <String, String>{'id': deviceId},
      body: <String, String>{
        'smdp': smdp,
        if (matchingId.isNotEmpty) 'matching_id': matchingId,
        if (confirmationCode.isNotEmpty) 'confirmation_code': confirmationCode,
        if (aidHex.isNotEmpty) 'aid_hex': aidHex,
      },
      timeout: const Duration(minutes: 10),
      cancellation: cancellation,
      onEvent: (SseEvent event) {
        if (event.name != 'progress' && event.name != 'message') return true;
        final decoded = jsonDecode(event.data);
        if (decoded is! Map<Object?, Object?>) {
          errorMessage = 'invalid';
          return false;
        }
        final step = decoded['step'];
        final msg = decoded['msg'];
        if (step is! String || msg is! String) {
          errorMessage = 'invalid';
          return false;
        }
        final pct = decoded['pct'];
        final percent = pct is int ? pct : (pct is num ? pct.toInt() : 0);
        final progress = EsimDownloadProgress(
          step: step,
          message: msg,
          percent: percent,
        );
        onProgress?.call(progress);
        if (progress.isError) {
          errorMessage = msg;
          return false;
        }
        if (progress.isDone) {
          done = true;
          return false;
        }
        return true;
      },
    );
    if (errorMessage == 'invalid') throw const EsimDtoException();
    if (errorMessage != null) throw EsimDownloadFailed(errorMessage!);
    if (!done) throw const EsimDtoException();
  }

  /// ========== eSIM 通知 API ==========

  /// 获取所有通知规则
  Future<List<EsimNotificationDto>> fetchNotifications(
    String deviceId, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: GatewayApi.deviceEsimUserNotifications,
      pathParameters: <String, String>{'id': deviceId},
      cancellation: cancellation,
    );
    if (data is! List) throw const EsimDtoException();
    return data
        .cast<Map<String, Object?>>()
        .map(EsimNotificationDto.fromBackendJson)
        .toList();
  }

  /// 创建通知规则
  Future<EsimNotificationDto> createNotification(
    String deviceId, {
    required String type,
    double? threshold,
    int? daysBeforeExpiry,
    bool enabled = true,
    RequestCancellation? cancellation,
  }) async {
    final body = <String, Object?>{
      'type': type,
      if (threshold != null) 'threshold': threshold,
      if (daysBeforeExpiry != null) 'days_before_expiry': daysBeforeExpiry,
      'enabled': enabled,
    };
    final data = await _transport.sendJson(
      method: 'POST',
      routeTemplate: GatewayApi.deviceEsimUserNotifications,
      pathParameters: <String, String>{'id': deviceId},
      body: body,
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return EsimNotificationDto.fromBackendJson(Map<String, Object?>.from(map));
  }

  /// 更新通知规则（仅支持切换启用状态）
  Future<EsimNotificationDto> updateNotification(
    String deviceId, {
    required String notificationId,
    required bool enabled,
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: GatewayApi.deviceEsimUserNotification,
      pathParameters: <String, String>{
        'id': deviceId,
        'nid': notificationId,
      },
      body: <String, bool>{'enabled': enabled},
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return EsimNotificationDto.fromBackendJson(Map<String, Object?>.from(map));
  }

  /// 删除通知规则
  Future<void> deleteNotification(
    String deviceId, {
    required String notificationId,
    RequestCancellation? cancellation,
  }) async {
    await _transport.sendJson(
      method: 'DELETE',
      routeTemplate: GatewayApi.deviceEsimUserNotification,
      pathParameters: <String, String>{
        'id': deviceId,
        'nid': notificationId,
      },
      cancellation: cancellation,
    );
  }
}
