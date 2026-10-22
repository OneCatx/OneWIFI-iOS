import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'esim_notification_dto.dart';

/// eSIM 用户告警本地迁移缓存（SharedPreferences）。
///
/// 真源已是 WEB `…/esim/user-notifications`；本 store 仅供
/// [EsimNotificationRepository.migrateLocalToBackend] 一次性上送后清空。
final class EsimNotificationLocalStore {
  EsimNotificationLocalStore({required this.deviceId});

  final String deviceId;

  String get _storageKey => 'esim_notifications_$deviceId';

  /// 加载所有通知规则
  Future<List<EsimNotificationDto>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) return const [];

    try {
      final jsonList = jsonDecode(jsonString) as List<Object?>;
      return jsonList
          .cast<Map<String, Object?>>()
          .map(EsimNotificationDto.fromLocalJson)
          .toList();
    } catch (e) {
      // 损坏的数据返回空表，不抛异常
      return const [];
    }
  }

  /// 保存所有通知规则
  Future<void> save(List<EsimNotificationDto> notifications) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = notifications.map((n) => n.toLocalJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  /// 清空所有通知规则
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
