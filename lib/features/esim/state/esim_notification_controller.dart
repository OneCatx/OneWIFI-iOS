import 'package:flutter/foundation.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../data/esim_notification_repository.dart';
import '../domain/esim_notification.dart';

/// eSIM 通知 Controller（Provider ChangeNotifier）
final class EsimNotificationController extends ChangeNotifier {
  EsimNotificationController({
    required String deviceId,
    required EsimNotificationRepository repository,
  }) : _repository = repository,
       _notifications = QueryState<List<EsimNotification>>.initial(
         key: 'esim.notifications:$deviceId',
       );

  final EsimNotificationRepository _repository;

  QueryState<List<EsimNotification>> _notifications;
  ActionState _createAction = const ActionState.idle();
  ActionState _deleteAction = const ActionState.idle();
  bool _migrated = false;

  QueryState<List<EsimNotification>> get notifications => _notifications;
  ActionState get createAction => _createAction;
  ActionState get deleteAction => _deleteAction;

  /// 加载所有通知规则（首次加载时自动迁移）
  Future<void> load() async {
    _notifications = QueryState.pending(
      previous: _notifications.lastGoodData,
      key: _notifications.key,
    );
    notifyListeners();

    // 首次加载时尝试迁移本地数据
    if (!_migrated) {
      try {
        await _repository.migrateLocalToBackend();
        _migrated = true;
      } catch (e) {
        // 迁移失败不影响正常加载
      }
    }

    try {
      final list = await _repository.getAll();
      _notifications = QueryState.data(data: list, key: _notifications.key);
    } catch (e) {
      _notifications = QueryState.failedAfter(
        e,
        previous: _notifications.lastGoodData,
        key: _notifications.key,
      );
    }
    notifyListeners();
  }

  /// 新增通知规则
  Future<void> create(EsimNotification notification) async {
    _createAction = const ActionState.submitting();
    notifyListeners();

    try {
      await _repository.create(notification);
      _createAction = const ActionState.succeeded();
      notifyListeners();
      // 创建成功后自动刷新列表
      await load();
    } catch (e) {
      _createAction = ActionState.fromError(e);
      notifyListeners();
    }
  }

  /// 删除通知规则
  Future<void> delete(String notificationId) async {
    _deleteAction = const ActionState.submitting();
    notifyListeners();

    try {
      await _repository.delete(notificationId);
      _deleteAction = const ActionState.succeeded();
      notifyListeners();
      // 删除成功后自动刷新列表
      await load();
    } catch (e) {
      _deleteAction = ActionState.fromError(e);
      notifyListeners();
    }
  }

  /// 切换通知规则的启用状态
  Future<void> toggleEnabled(String notificationId) async {
    final current = _notifications.lastGoodData;
    if (current == null) return;

    final index = current.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;

    final updated = current[index].copyWith(enabled: !current[index].enabled);
    try {
      await _repository.update(updated);
      await load();
    } catch (e) {
      // 失败时静默处理，用户会看到未变化
    }
  }

  /// 重置创建操作状态（对话框关闭时调用）
  void resetCreateAction() {
    _createAction = const ActionState.idle();
    notifyListeners();
  }

  /// 重置删除操作状态
  void resetDeleteAction() {
    _deleteAction = const ActionState.idle();
    notifyListeners();
  }
}
