import '../domain/esim_notification.dart';
import 'esim_api.dart';
import 'esim_notification_local_store.dart';

/// eSIM 通知 Repository（后端 API + 本地迁移）
final class EsimNotificationRepository {
  EsimNotificationRepository({
    required this.deviceId,
    required this.api,
    EsimNotificationLocalStore? localStore,
  }) : _localStore = localStore;

  final String deviceId;
  final EsimApi api;
  final EsimNotificationLocalStore? _localStore;

  /// 获取所有通知规则（从后端）
  Future<List<EsimNotification>> getAll() async {
    final dtos = await api.fetchNotifications(deviceId);
    return dtos.map((dto) => dto.toDomain()).toList();
  }

  /// 新增通知规则
  Future<void> create(EsimNotification notification) async {
    await api.createNotification(
      deviceId,
      type: notification.type.value,
      threshold: notification.threshold?.value,
      daysBeforeExpiry: notification.daysBeforeExpiry?.value,
      enabled: notification.enabled,
    );
  }

  /// 更新通知规则（仅支持切换启用状态）
  Future<void> update(EsimNotification notification) async {
    await api.updateNotification(
      deviceId,
      notificationId: notification.id,
      enabled: notification.enabled,
    );
  }

  /// 删除通知规则
  Future<void> delete(String notificationId) async {
    await api.deleteNotification(
      deviceId,
      notificationId: notificationId,
    );
  }

  /// 清空所有规则（测试用）
  Future<void> deleteAll() async {
    final all = await getAll();
    for (final notification in all) {
      await delete(notification.id);
    }
  }

  /// 迁移本地数据到后端（一次性，启动时调用）
  Future<void> migrateLocalToBackend() async {
    if (_localStore == null) return;

    try {
      // 读取本地数据
      final localDtos = await _localStore.load();
      if (localDtos.isEmpty) return;

      // 上传到后端（逐个创建）
      for (final dto in localDtos) {
        try {
          await api.createNotification(
            deviceId,
            type: dto.type,
            threshold: dto.threshold,
            daysBeforeExpiry: dto.daysBeforeExpiry,
            enabled: dto.enabled,
          );
        } catch (e) {
          // 单条失败不影响其他迁移，继续
        }
      }

      // 迁移成功，清空本地数据
      await _localStore.clear();
    } catch (e) {
      // 迁移失败静默处理，下次启动再试
    }
  }
}
