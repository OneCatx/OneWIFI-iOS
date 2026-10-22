import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/glass_dialog.dart';
import '../../data/ios_apns_bridge.dart';
import '../../state/otp_activity_binding.dart';
import '../../state/remote_otp_controller.dart';
import '../../state/sms_controller.dart';

/// OneTools 配对与实时活动测试，由设置页提供入口。
final class RemoteOtpPairingTile extends StatefulWidget {
  const RemoteOtpPairingTile({required this.controller, super.key});

  static const Key cardKey = Key('sms-remote-otp-card');
  static const Key pairKey = Key('sms-remote-otp-pair');
  static const Key activityTestKey = Key('sms-otp-activity-test');
  static const Key pushActionKey = Key('sms-remote-otp-push-action');
  static const Key disconnectKey = Key('sms-remote-otp-disconnect');
  static const String buildMarker = 'OTP-PAIR-58';

  final SmsController controller;

  @override
  State<RemoteOtpPairingTile> createState() => _RemoteOtpPairingTileState();
}

final class _RemoteOtpPairingTileState extends State<RemoteOtpPairingTile> {
  @override
  void initState() {
    super.initState();
    unawaited(_refreshAuthorization());
  }

  Future<void> _refreshAuthorization() async {
    final remote = widget.controller.remoteOtpController;
    if (remote == null) return;
    await remote.apns.refreshAuthorization();
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.controller.remoteOtpController;
    final theme = Theme.of(context);
    final state = remote?.state;
    return GlassTile(
      key: RemoteOtpPairingTile.cardKey,
      semanticLabel: '远程验证码配对 ${RemoteOtpPairingTile.buildMarker}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.link_outlined, color: theme.colorScheme.onSurface),
              const SizedBox(width: OneSpacing.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('远程验证码', style: theme.textTheme.titleSmall),
                    const SizedBox(height: OneSpacing.nano),
                    Text(
                      state == null ? '远程验证码组件未加载' : _description(state),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state?.paired == true)
                Padding(
                  padding: const EdgeInsets.only(left: OneSpacing.small),
                  child: TextButton(
                    key: RemoteOtpPairingTile.disconnectKey,
                    onPressed: remote?.disconnect,
                    child: const Text('断开'),
                  ),
                ),
            ],
          ),
          if (remote != null) ...<Widget>[
            const SizedBox(height: OneSpacing.item),
            ValueListenableBuilder<IosApnsStatus>(
              valueListenable: remote.apns.status,
              builder: (context, status, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _PushNotice(
                    notice: _pushNotice(status),
                    onRequestAuthorization: () =>
                        unawaited(remote.apns.requestAuthorization()),
                    onOpenSettings: () =>
                        unawaited(remote.apns.openNotificationSettings()),
                  ),
                  const SizedBox(height: OneSpacing.nano),
                  ListenableBuilder(
                    listenable: remote.activity,
                    builder: (context, _) => _NoticeRow(
                      icon: Icons.bolt_outlined,
                      message: _activityDescription(remote.activity.readiness),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: OneSpacing.item),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: RemoteOtpPairingTile.pairKey,
              onPressed: remote == null
                  ? null
                  : () => _showPairingDialog(context, remote),
              icon: const Icon(Icons.content_paste_go, size: 18),
              label: Text(state?.paired == true ? '重新配对' : '粘贴 OneTools 配对链接'),
            ),
          ),
          if (remote != null)
            OutlinedButton.icon(
              key: RemoteOtpPairingTile.activityTestKey,
              onPressed: () => _showActivityTest(context),
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('准备接收活动'),
            ),
        ],
      ),
    );
  }

  /// 把原生推送事实翻译成一句人话加一个动作，避免用户无从判断卡在哪一环。
  _PushNoticeModel _pushNotice(IosApnsStatus status) {
    if (status.registrationError.isNotEmpty) {
      return _PushNoticeModel(
        message: '推送地址登记失败：${status.registrationError}',
        action: '重试授权',
        actionKey: _PushAction.requestAuthorization,
        isError: true,
      );
    }
    if (!status.registered) {
      return const _PushNoticeModel(
        message: '推送地址尚未登记，后台验证码无法送达。',
        action: '开启通知权限',
        actionKey: _PushAction.requestAuthorization,
        isError: true,
      );
    }
    return switch (status.authorization) {
      IosPushAuthorization.notDetermined => const _PushNoticeModel(
        message: '系统通知权限未开启，后台验证码不会显示。',
        action: '开启通知权限',
        actionKey: _PushAction.requestAuthorization,
        isError: true,
      ),
      IosPushAuthorization.denied => const _PushNoticeModel(
        message: '通知权限已被拒绝，后台验证码不会显示。',
        action: '去系统设置',
        actionKey: _PushAction.openSettings,
        isError: true,
      ),
      _ when !status.alertsEnabled => const _PushNoticeModel(
        message: '通知已授权，但横幅被关闭，验证码只会静默进入通知中心。',
        action: '去系统设置',
        actionKey: _PushAction.openSettings,
      ),
      _ => const _PushNoticeModel(message: '后台推送已就绪。'),
    };
  }

  Future<void> _showActivityTest(BuildContext context) async {
    final remote = widget.controller.remoteOtpController;
    if (remote == null) return;
    final request = remote.activity.prepareExplicitly().then(
      (_) => _activityDescription(remote.activity.readiness),
    );
    await showOneGlassPopup<void>(
      context: context,
      heightFactor: null,
      builder: (popupContext) => Padding(
        padding: const EdgeInsets.all(OneSpacing.medium),
        child: FutureBuilder<String>(
          future: request,
          builder: (context, snapshot) {
            final message = snapshot.data ?? '正在准备接收活动…';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('接收活动', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: OneSpacing.item),
                Text(message),
                const SizedBox(height: OneSpacing.item),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(popupContext).pop(),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _activityDescription(OtpActivityReadiness value) => switch (value) {
    OtpActivityReadiness.ready => '接收活动就绪。最长保留 8 小时；关闭或到期后仍有普通通知，下次打开 App 恢复。',
    OtpActivityReadiness.waiting => '接收活动等待就绪。请先完成配对并保持 App 在前台。',
    OtpActivityReadiness.unavailable => '接收活动已关闭或到期。普通通知照常，下次打开 App 恢复。',
    OtpActivityReadiness.upgradeRequired => '网关需升级，接收活动未就绪。',
    OtpActivityReadiness.clockError => '设备时间与网关不一致，请校准时间后重新打开 App。',
  };

  String _description(RemoteOtpState state) => switch (state.status) {
    RemoteOtpStatus.unpaired => '粘贴 OneTools 配对链接，接收网页端验证码。',
    RemoteOtpStatus.connecting => '正在连接 ${state.endpoint}',
    RemoteOtpStatus.connected => '已连接 ${state.endpoint}',
    RemoteOtpStatus.retrying => state.error ?? '连接中断，正在重试。',
    RemoteOtpStatus.unauthorized => '令牌无效，请重新配对。',
  };

  Future<void> _showPairingDialog(
    BuildContext context,
    RemoteOtpController controller,
  ) async {
    final input = TextEditingController();
    String? error;
    await showOneGlassPopup<void>(
      context: context,
      heightFactor: null,
      builder: (popupContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(OneSpacing.medium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('配对远程验证码', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: OneSpacing.item),
              TextField(
                key: const Key('sms-remote-otp-input'),
                controller: input,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'onetools://onewifi?…',
                  errorText: error,
                ),
              ),
              const SizedBox(height: OneSpacing.item),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: OneSpacing.small,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(popupContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final raw = input.text.trim();
                      if (raw.isEmpty) {
                        setState(() => error = '请粘贴配对链接');
                        return;
                      }
                      try {
                        await controller.pair(raw);
                        if (popupContext.mounted) {
                          Navigator.of(popupContext).pop();
                        }
                      } catch (e) {
                        setState(() => error = e.toString());
                      }
                    },
                    child: const Text('连接'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    input.dispose();
  }
}

enum _PushAction { requestAuthorization, openSettings }

final class _PushNoticeModel {
  const _PushNoticeModel({
    required this.message,
    this.action,
    this.actionKey,
    this.isError = false,
  });

  final String message;
  final String? action;
  final _PushAction? actionKey;
  final bool isError;
}

/// 推送事实行：状态图标 + 一句话 + 可选动作。横幅与灵动岛各占一行，
/// 样式保持一致，避免用户以为只有一条推送通道。
final class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.icon,
    required this.message,
    this.isError = false,
    this.action,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: 16,
          color: isError
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: OneSpacing.nano),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?action,
      ],
    );
  }
}

final class _PushNotice extends StatelessWidget {
  const _PushNotice({
    required this.notice,
    required this.onRequestAuthorization,
    required this.onOpenSettings,
  });

  final _PushNoticeModel notice;
  final VoidCallback onRequestAuthorization;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final action = notice.action;
    final actionKey = notice.actionKey;
    return _NoticeRow(
      icon: notice.isError
          ? Icons.error_outline
          : Icons.notifications_active_outlined,
      message: notice.message,
      isError: notice.isError,
      action: action != null && actionKey != null
          ? TextButton(
              key: RemoteOtpPairingTile.pushActionKey,
              onPressed: switch (actionKey) {
                _PushAction.requestAuthorization => onRequestAuthorization,
                _PushAction.openSettings => onOpenSettings,
              },
              child: Text(action),
            )
          : null,
    );
  }
}
