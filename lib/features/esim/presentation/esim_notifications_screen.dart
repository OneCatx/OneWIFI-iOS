import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../data/esim_api.dart';
import '../data/esim_notification_local_store.dart';
import '../data/esim_notification_repository.dart';
import '../domain/esim_notification.dart';
import '../state/esim_notification_controller.dart';

/// eSIM 通知管理屏幕（流量告警 / 到期提醒）
///
/// 后端 API 已对接，支持三端数据同步。
final class EsimNotificationsScreen extends StatefulWidget {
  const EsimNotificationsScreen({
    required this.deviceId,
    required this.api,
    super.key,
  });

  final String deviceId;
  final EsimApi api;

  @override
  State<EsimNotificationsScreen> createState() =>
      _EsimNotificationsScreenState();
}

final class _EsimNotificationsScreenState
    extends State<EsimNotificationsScreen> {
  late final EsimNotificationController _controller;

  @override
  void initState() {
    super.initState();
    final localStore = EsimNotificationLocalStore(deviceId: widget.deviceId);
    final repository = EsimNotificationRepository(
      deviceId: widget.deviceId,
      api: widget.api,
      localStore: localStore,
    );
    _controller = EsimNotificationController(
      deviceId: widget.deviceId,
      repository: repository,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('eSIM 通知管理'),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        body: const _NotificationsList(),
        floatingActionButton: const _AddNotificationButton(),
      ),
    );
  }
}

final class _NotificationsList extends StatelessWidget {
  const _NotificationsList();

  @override
  Widget build(BuildContext context) {
    return Consumer<EsimNotificationController>(
      builder: (context, controller, _) {
        final state = controller.notifications;

        return switch (state.status) {
          QueryStatus.initial || QueryStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          QueryStatus.data || QueryStatus.refreshing => _buildList(
              context,
              controller,
              state.lastGoodData ?? const [],
              state.status == QueryStatus.refreshing,
            ),
          QueryStatus.empty => _buildEmptyState(context),
          QueryStatus.failed => _buildErrorState(context, state, controller),
        };
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    EsimNotificationController controller,
    List<EsimNotification> notifications,
    bool refreshing,
  ) {
    if (notifications.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: () => controller.load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(OneSpacing.medium),
        itemCount: notifications.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: OneSpacing.item),
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return _NotificationCard(
            notification: notification,
            onDelete: () => _confirmDelete(context, controller, notification),
            onToggle: () => controller.toggleEnabled(notification.id),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.notifications_none,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: OneSpacing.medium),
          Text(
            '还没有设置通知规则',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: OneSpacing.small),
          Text(
            '点击右下角按钮添加第一条规则',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    QueryState<List<EsimNotification>> state,
    EsimNotificationController controller,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: OneSpacing.medium),
          Text(
            '加载失败',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: OneSpacing.small),
          Text(
            state.failure?.message ?? '未知错误',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: OneSpacing.medium),
          ElevatedButton.icon(
            onPressed: () => controller.load(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    EsimNotificationController controller,
    EsimNotification notification,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除通知规则「${notification.displayTitle}」？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await controller.delete(notification.id);
    }
  }
}

final class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onDelete,
    required this.onToggle,
  });

  final EsimNotification notification;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OneSpacing.medium,
          vertical: OneSpacing.small,
        ),
        leading: Icon(
          _getIcon(),
          color: notification.enabled
              ? colorScheme.primary
              : colorScheme.onSurface.withOpacity(0.4),
        ),
        title: Text(
          notification.displayTitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: notification.enabled
                ? null
                : colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
        subtitle: Text(
          notification.displaySubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: notification.enabled
                ? colorScheme.onSurface.withOpacity(0.7)
                : colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Switch(
              value: notification.enabled,
              onChanged: (_) => onToggle(),
            ),
            const SizedBox(width: OneSpacing.small),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: colorScheme.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    return switch (notification.type) {
      EsimNotificationType.trafficThreshold => Icons.data_usage,
      EsimNotificationType.expiryReminder => Icons.event_available,
    };
  }
}

final class _AddNotificationButton extends StatelessWidget {
  const _AddNotificationButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<EsimNotificationController>(
      builder: (context, controller, _) {
        final busy =
            controller.notifications.status == QueryStatus.loading ||
            controller.createAction.status == ActionStatus.submitting;

        return FloatingActionButton.extended(
          onPressed: busy ? null : () => _showAddDialog(context, controller),
          icon: const Icon(Icons.add),
          label: const Text('新增规则'),
        );
      },
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    EsimNotificationController controller,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AddNotificationDialog(controller: controller),
    );
  }
}

final class _AddNotificationDialog extends StatefulWidget {
  const _AddNotificationDialog({required this.controller});

  final EsimNotificationController controller;

  @override
  State<_AddNotificationDialog> createState() => _AddNotificationDialogState();
}

final class _AddNotificationDialogState
    extends State<_AddNotificationDialog> {
  EsimNotificationType _type = EsimNotificationType.trafficThreshold;
  TrafficThreshold _threshold = TrafficThreshold.percent80;
  ExpiryDays _days = ExpiryDays.days7;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final action = widget.controller.createAction;
    if (action.status == ActionStatus.succeeded) {
      widget.controller.resetCreateAction();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('规则已添加')),
      );
    } else if (action.status == ActionStatus.failed) {
      final message = action.knownFailure?.message ?? '添加失败';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      widget.controller.resetCreateAction();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增通知规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '通知类型',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: OneSpacing.small),
            ..._buildTypeSelector(),
            const SizedBox(height: OneSpacing.medium),
            if (_type == EsimNotificationType.trafficThreshold)
              ..._buildThresholdSelector()
            else
              ..._buildDaysSelector(),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _onConfirm,
          child: const Text('添加'),
        ),
      ],
    );
  }

  List<Widget> _buildTypeSelector() {
    return [
      RadioListTile<EsimNotificationType>(
        value: EsimNotificationType.trafficThreshold,
        groupValue: _type,
        onChanged: (value) {
          if (value != null) setState(() => _type = value);
        },
        title: Text(EsimNotificationType.trafficThreshold.displayName),
        dense: true,
      ),
      RadioListTile<EsimNotificationType>(
        value: EsimNotificationType.expiryReminder,
        groupValue: _type,
        onChanged: (value) {
          if (value != null) setState(() => _type = value);
        },
        title: Text(EsimNotificationType.expiryReminder.displayName),
        dense: true,
      ),
    ];
  }

  List<Widget> _buildThresholdSelector() {
    return [
      const Text(
        '流量阈值',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: OneSpacing.small),
      SegmentedButton<TrafficThreshold>(
        segments: TrafficThreshold.values
            .map((t) => ButtonSegment(
                  value: t,
                  label: Text(t.displayName),
                ))
            .toList(),
        selected: {_threshold},
        onSelectionChanged: (selected) {
          setState(() => _threshold = selected.first);
        },
      ),
    ];
  }

  List<Widget> _buildDaysSelector() {
    return [
      const Text(
        '提前天数',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: OneSpacing.small),
      SegmentedButton<ExpiryDays>(
        segments: ExpiryDays.values
            .map((d) => ButtonSegment(
                  value: d,
                  label: Text(d.displayName),
                ))
            .toList(),
        selected: {_days},
        onSelectionChanged: (selected) {
          setState(() => _days = selected.first);
        },
      ),
    ];
  }

  void _onConfirm() {
    final notification = EsimNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: _type,
      threshold:
          _type == EsimNotificationType.trafficThreshold ? _threshold : null,
      daysBeforeExpiry:
          _type == EsimNotificationType.expiryReminder ? _days : null,
      enabled: true,
    );

    widget.controller.create(notification);
  }
}
