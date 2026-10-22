import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/state_failure.dart';
import '../../../design/theme/one_theme.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../../../design/widgets/system_controls.dart';
import '../../esim/domain/card_policy.dart';
import '../../esim/domain/esim.dart';
import '../../esim/domain/euicc_hardware.dart';
import '../../esim/presentation/esim_panel.dart';
import '../../esim/presentation/widgets/mbn_profile_field.dart';
import '../../esim/state/esim_controller.dart';
import '../data/device_repository.dart';
import '../domain/device.dart';
import '../state/device_detail_controller.dart';

part 'device_detail_policy_panel.dart';
part 'device_detail_runtime_panel.dart';
part 'device_detail_sim_panel.dart';

/// 设备详情：照搬 WEB `OneWifiInstanceCard` 选中设备后的总览区。
/// 顺序：运行状态（含当前进度）→ SIM / 设备 → 切卡（顶上切卡进度）→ 卡策略。
final class DeviceDetailView extends StatefulWidget {
  const DeviceDetailView({
    required this.controller,
    required this.onBack,
    this.esimController,
    super.key,
  });

  static const Key apnFieldKey = Key('device-policy-apn-field');

  final DeviceDetailController controller;
  final VoidCallback onBack;
  final EsimController? esimController;

  @override
  State<DeviceDetailView> createState() => _DeviceDetailViewState();
}

final class _DeviceDetailViewState extends State<DeviceDetailView> {
  /// WEB 切卡时把轮询压到 500ms；App 走 1s——够看清五段推进，又不把网关打爆。
  static const Duration _switchPollInterval = Duration(seconds: 1);

  Timer? _switchPoll;
  Future<void>? _automaticPoll;
  int _pollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _attach(widget);
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(DeviceDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    if (controllerChanged ||
        !identical(oldWidget.esimController, widget.esimController)) {
      _switchPoll?.cancel();
      _switchPoll = null;
      _automaticPoll = null;
      _pollGeneration++;
      _detach(oldWidget);
      _attach(widget);
      _syncSwitchPolling();
    }
    if (controllerChanged) _scheduleLoad();
  }

  @override
  void dispose() {
    _pollGeneration++;
    _detach(widget);
    _switchPoll?.cancel();
    super.dispose();
  }

  void _attach(DeviceDetailView target) {
    target.controller.addListener(_syncSwitchPolling);
    target.esimController?.addListener(_syncSwitchPolling);
  }

  void _detach(DeviceDetailView target) {
    target.controller.removeListener(_syncSwitchPolling);
    target.esimController?.removeListener(_syncSwitchPolling);
  }

  void _scheduleLoad() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(controller, widget.controller)) {
        controller.load();
      }
    });
  }

  bool get _switching =>
      widget.esimController?.switchAction.status == ActionStatus.submitting ||
      (widget.controller.state.lastGoodData?.device.esimSwitch.active ?? false);

  /// 切卡进行中（本机发起，或网关快照说 active）就定时静默拉设备快照，
  /// 让「切卡进度」五段跟着后端推进；结束时再补拉一次拿最终态。
  void _syncSwitchPolling() {
    if (!mounted) return;
    final switching = _switching;
    if (switching && _switchPoll == null) {
      _pollGeneration++;
      final controller = widget.controller;
      _switchPoll = Timer.periodic(_switchPollInterval, (_) {
        if (mounted && identical(controller, widget.controller)) {
          _requestAutomaticPoll();
        }
      });
    } else if (!switching && _switchPoll != null) {
      _switchPoll!.cancel();
      _switchPoll = null;
      unawaited(_finishSwitchPolling());
    }
  }

  void _requestAutomaticPoll() {
    if (_automaticPoll != null) return;
    final pending = widget.controller.poll(automatic: true);
    _automaticPoll = pending;
    unawaited(
      pending.whenComplete(() {
        if (identical(_automaticPoll, pending)) _automaticPoll = null;
      }),
    );
  }

  Future<void> _finishSwitchPolling() async {
    final controller = widget.controller;
    final generation = _pollGeneration;
    // An overview begun before local switch completion may still contain the
    // old inactive snapshot. Finish that read, then take one final snapshot.
    await _automaticPoll;
    if (!mounted ||
        controller.isDisposed ||
        !identical(controller, widget.controller) ||
        generation != _pollGeneration ||
        _switching) {
      return;
    }
    // Unlike a timer tick, this reconciliation must not be skipped behind a
    // pre-completion manual refresh. Keep the explicit latest-read contract.
    await controller.poll();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge(<Listenable>[
      widget.controller,
      ?widget.esimController,
    ]),
    builder: (context, _) {
      final padding = OneInsets.scroll(context);
      final missing = widget.controller.state.failure?.statusCode == 404;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              0,
            ),
            child: _BackButton(
              onBack: widget.onBack,
              label: missing ? '返回设备列表' : '返回',
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  OneSpacing.item,
                  padding.right,
                  padding.bottom,
                ),
                children: _content(widget.controller.state),
              ),
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _content(QueryState<DeviceDetail> state) {
    final detail = state.lastGoodData;
    if (state.failure?.statusCode == 404) {
      return const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.attention,
          title: '设备已不存在',
          message: '回到设备列表另选一台。',
        ),
      ];
    }
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.neutral,
          title: '正在加载设备',
          message: '正在读取设备状态。',
        ),
        SizedBox(height: OneSpacing.medium),
        Center(
          child: OneStatusProgress(
            label: '正在加载设备',
            kind: OneProgressKind.circular,
          ),
        ),
      ];
    }
    if (detail == null) {
      final forbidden = state.failure?.kind == StateFailureKind.forbidden;
      return <Widget>[
        OneStatusHero(
          tone: forbidden ? OneStatusTone.critical : OneStatusTone.attention,
          title: forbidden ? '无权访问该设备' : '设备不可用',
          message: '设备详情加载失败，下拉刷新重试。',
        ),
      ];
    }

    final refreshing = state.status == QueryStatus.refreshing;
    final stale = state.status == QueryStatus.failed && state.isStale;
    final submitting =
        widget.controller.action.status == ActionStatus.submitting;
    return <Widget>[
      OwPageHead(
        title: detail.device.name,
        desc: detail.device.physicalPresent ? '设备状态已就绪。' : '设备已配置但离线',
      ),
      if (refreshing) ...const <Widget>[
        SizedBox(height: OneSpacing.item),
        OneStatusProgress(label: '正在刷新设备', kind: OneProgressKind.linear),
      ],
      if (stale) ...const <Widget>[
        SizedBox(height: OneSpacing.item),
        OneStatusHero(
          tone: OneStatusTone.attention,
          title: '显示的是上次的设备数据',
          message: '刷新没有完成，当前内容可能已过期。',
        ),
      ],
      const SizedBox(height: OneSpacing.medium),
      _RuntimePanel(device: detail.device, onReconnect: _confirmReconnect),
      const SizedBox(height: OneSpacing.medium),
      _SimPanel(
        detail: detail,
        esim: widget.esimController,
        onReboot: _confirmReboot,
      ),
      ..._actionOutcome(),
      if (widget.esimController case final esim?)
        EsimPanel(
          controller: esim,
          imeiDisplay: detail.device.identities.imeiDisplay,
          deviceOnline:
              detail.device.physicalPresent || detail.device.controlOnline,
          header: _SwitchProgressPanel(
            progress: detail.device.esimSwitch,
            switching: _switching,
          ),
        ),
      const SizedBox(height: OneSpacing.medium),
      _CardPolicyPanel(
        device: detail.device,
        esim: widget.esimController,
        submitting: submitting,
        onNetwork: (value) =>
            widget.controller.setCapability(DeviceCapability.network, value),
        onVowifi: (value) =>
            widget.controller.setCapability(DeviceCapability.vowifi, value),
        onFlight: (value) =>
            widget.controller.setCapability(DeviceCapability.flightMode, value),
      ),
    ];
  }

  List<Widget> _actionOutcome() {
    final action = widget.controller.action;
    if (action.status == ActionStatus.failed) {
      return <Widget>[
        const SizedBox(height: OneSpacing.item),
        OneStatusHero(
          tone: OneStatusTone.critical,
          title: action.isUnknownOutcome ? '操作结果未知' : '操作失败',
          message: action.isUnknownOutcome
              ? '超时或断线，不会自动重试。'
              : action.knownFailure?.kind == StateFailureKind.conflict
              ? '当前卡策略不允许这项改动。'
              : '网关拒绝了这项改动。',
        ),
      ];
    }
    return const <Widget>[];
  }

  Future<void> _confirmReconnect() async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '重连 VoWiFi?',
      message: '重连当前 VoWiFi 会话，不会自动重试。',
      confirmLabel: '重连',
    );
    if (confirmed == true && mounted) {
      await widget.controller.reconnectVowifi();
    }
  }

  Future<void> _confirmReboot() async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '重启模组?',
      message: '重启这台模组，数据和短信会中断。',
      confirmLabel: '重启',
    );
    if (confirmed == true && mounted) await widget.controller.reboot();
  }
}

final class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack, this.label = '返回'});
  final VoidCallback onBack;
  final String label;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      height: OneSizes.minimumTarget,
      child: label == '返回'
          ? IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const SystemIcon(Icons.arrow_back),
            )
          : FilledButton.icon(
              onPressed: onBack,
              icon: const SystemIcon(Icons.arrow_back),
              label: Text(label),
            ),
    ),
  );
}

String _value(String value) => value.isEmpty ? '未上报' : value;

String _traffic(DeviceTraffic traffic) => !traffic.available
    ? '流量不可用'
    : '流量 · ↓ ${_bytes(traffic.rxBytes!)} · ↑ ${_bytes(traffic.txBytes!)}';

String _bytes(int bytes) => bytes == 0 ? '0 B' : '$bytes B';
