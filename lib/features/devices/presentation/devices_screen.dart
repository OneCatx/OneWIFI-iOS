import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/device.dart';
import '../state/device_list_controller.dart';
import 'device_register_dialog.dart';
import 'discovered_device_card.dart';
import 'fleet_device_card.dart';

final class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    required this.controller,
    required this.onDeviceSelected,
    super.key,
  });

  final DeviceListController controller;
  final ValueChanged<String> onDeviceSelected;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

final class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(DevicesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) _scheduleLoad();
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.load();
        widget.controller.loadDiscoveredDevices();
      }
    });
  }

  Future<void> _handleRescan() async {
    try {
      await widget.controller.rescanDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设备扫描完成')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $error')),
      );
    }
  }

  Future<void> _handleRegister(DiscoveredDevice device) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => DeviceRegisterDialog(device: device),
    );
    if (result == null || !mounted) return;

    try {
      await widget.controller.registerDevice(
        deviceId: result['deviceId']!,
        discoveryKey: result['discoveryKey']!,
        deviceType: result['deviceType']!,
        name: result['name'],
        simPin: result['simPin']?.isEmpty ?? true ? null : result['simPin'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设备 ${result['name'] ?? result['deviceId']} 注册成功')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册失败: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final discoveredState = widget.controller.discoveredState;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: widget.controller.refresh,
            child: _listFor(state, discoveredState),
          ),
          floatingActionButton: widget.controller.isRescanning
              ? null
              : FloatingActionButton.extended(
                  onPressed: _handleRescan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新扫描'),
                ),
        );
      },
    );
  }

  Widget _listFor(
    QueryState<DeviceFleet> state,
    QueryState<List<DiscoveredDevice>> discoveredState,
  ) {
    final fleet = state.lastGoodData;
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OneInsets.scroll(context),
        children: <Widget>[
          ..._loadingFleetHeaders(),
          const SizedBox(height: OneSpacing.large),
          ..._discoveredSection(discoveredState),
        ],
      );
    }
    if (state.status == QueryStatus.empty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OneInsets.scroll(context),
        children: <Widget>[
          const OneStatusHero(
            tone: OneStatusTone.attention,
            title: '没有设备',
            message: '网关没有上报已配置的模组，下拉刷新重试。',
          ),
          const SizedBox(height: OneSpacing.large),
          ..._discoveredSection(discoveredState),
        ],
      );
    }
    if (fleet == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OneInsets.scroll(context),
        children: <Widget>[
          const OneStatusHero(
            tone: OneStatusTone.critical,
            title: '设备列表不可用',
            message: '设备数据加载失败，下拉刷新重试。',
          ),
          const SizedBox(height: OneSpacing.large),
          ..._discoveredSection(discoveredState),
        ],
      );
    }

    final refreshing = state.status == QueryStatus.refreshing;
    final stale = state.status == QueryStatus.failed && state.isStale;
    final devices = fleet.devices;
    final discoveredHeaders = _discoveredHeaders(discoveredState);
    final discoveredDevices = _unregisteredDevices(discoveredState);
    final needsDiscovered =
        discoveredHeaders.isNotEmpty || discoveredDevices.isNotEmpty;

    // Android T1 同源 ListView.builder：可增长设备卡懒构建。
    // 头部各块仍按独立 item 铺开（与改前 children 同形），避免刷新指示语义被
    // 收进单一 Column 后测不到。
    final headers = <Widget>[
      OwPageHead(
        title: '设备管理',
        desc: '${devices.length} 台已配置模组',
      ),
      if (refreshing) ...const <Widget>[
        SizedBox(height: OneSpacing.item),
        OneStatusProgress(
          label: '正在刷新设备列表',
          kind: OneProgressKind.linear,
        ),
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
      MetricRow(
        children: <Widget>[
          MetricCard(
            label: '设备总数',
            value: '${devices.length}',
            sub: '已配置 ${fleet.deviceLimit} 台额度',
            icon: Icons.devices_other_outlined,
            tone: MetricTone.blue,
          ),
          MetricCard(
            label: '在线设备',
            value:
                '${devices.where((device) => device.controlOnline).length}',
            sub: '控制面在线',
            icon: Icons.favorite_border,
            tone: MetricTone.green,
          ),
          MetricCard(
            label: '离线设备',
            value:
                '${devices.where((device) => !device.controlOnline).length}',
            sub: devices.any((device) => !device.controlOnline)
                ? '控制面离线'
                : '暂无设备离线',
            icon: Icons.wifi_off_outlined,
            tone: MetricTone.purple,
          ),
          MetricCard(
            label: '最近刷新',
            value: refreshing ? '刷新中' : '下拉刷新',
            sub: stale ? '上次的数据' : '列表与详情同源',
            icon: Icons.update,
            tone: MetricTone.blue,
          ),
        ],
      ),
      const SizedBox(height: OneSpacing.medium),
    ];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: OneInsets.scroll(context),
      itemCount: headers.length +
          devices.length +
          (needsDiscovered ? 1 + discoveredHeaders.length + discoveredDevices.length : 0),
      itemBuilder: (context, index) {
        if (index < headers.length) {
          return headers[index];
        }

        final deviceIndex = index - headers.length;
        if (deviceIndex < devices.length) {
          final device = devices[deviceIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: OneSpacing.medium),
            child: FleetDeviceCard(
              device: device,
              hardware: widget.controller.hardwareFor(device.id),
              selectedCardName:
                  widget.controller.enabledCardNameFor(device.id) ?? '',
              brandNameplate: widget.controller.brandNameplateFor(device.id),
              onTap: () => widget.onDeviceSelected(device.id),
            ),
          );
        }

        final afterFleet = index - headers.length - devices.length;
        if (afterFleet == 0) {
          return const SizedBox(height: OneSpacing.large);
        }
        final discoveredIndex = afterFleet - 1;
        if (discoveredIndex < discoveredHeaders.length) {
          return discoveredHeaders[discoveredIndex];
        }
        final device = discoveredDevices[
            discoveredIndex - discoveredHeaders.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: OneSpacing.medium),
          child: DiscoveredDeviceCard(
            device: device,
            onRegister: () => _handleRegister(device),
          ),
        );
      },
    );
  }

  List<Widget> _loadingFleetHeaders() => const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.neutral,
          title: '正在加载设备',
          message: '正在读取已配置的模组。',
        ),
        SizedBox(height: OneSpacing.medium),
        Center(
          child: OneStatusProgress(
            label: '正在加载设备',
            kind: OneProgressKind.circular,
          ),
        ),
      ];

  List<Widget> _discoveredSection(
    QueryState<List<DiscoveredDevice>> state,
  ) =>
      <Widget>[
        ..._discoveredHeaders(state),
        for (final device in _unregisteredDevices(state))
          Padding(
            padding: const EdgeInsets.only(bottom: OneSpacing.medium),
            child: DiscoveredDeviceCard(
              device: device,
              onRegister: () => _handleRegister(device),
            ),
          ),
      ];

  List<DiscoveredDevice> _unregisteredDevices(
    QueryState<List<DiscoveredDevice>> state,
  ) {
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return const <DiscoveredDevice>[];
    }
    final devices = state.lastGoodData ?? const <DiscoveredDevice>[];
    return devices.where((d) => d.isUnregistered).toList(growable: false);
  }

  List<Widget> _discoveredHeaders(QueryState<List<DiscoveredDevice>> state) {
    if (state.status == QueryStatus.initial) {
      return const <Widget>[];
    }
    if (state.status == QueryStatus.loading) {
      return const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.neutral,
          title: '正在扫描设备',
          message: '正在查找未注册的设备。',
        ),
        SizedBox(height: OneSpacing.medium),
        Center(
          child: OneStatusProgress(
            label: '正在扫描设备',
            kind: OneProgressKind.circular,
          ),
        ),
      ];
    }

    final devices = state.lastGoodData ?? const <DiscoveredDevice>[];
    final unregistered =
        devices.where((d) => d.isUnregistered).toList(growable: false);

    if (unregistered.isEmpty) {
      if (state.status == QueryStatus.empty || devices.isEmpty) {
        return const <Widget>[
          OwPageHead(title: '发现的设备', desc: '未找到新设备'),
          SizedBox(height: OneSpacing.medium),
          OneStatusHero(
            tone: OneStatusTone.neutral,
            title: '没有发现新设备',
            message: '点击右下角「重新扫描」按钮查找新设备。',
          ),
        ];
      }
      return const <Widget>[];
    }

    final refreshing = state.status == QueryStatus.refreshing;
    return <Widget>[
      OwPageHead(
        title: '发现的设备',
        desc: '${unregistered.length} 台未注册设备',
      ),
      if (refreshing) ...const <Widget>[
        SizedBox(height: OneSpacing.item),
        OneStatusProgress(label: '正在刷新发现列表', kind: OneProgressKind.linear),
      ],
      const SizedBox(height: OneSpacing.medium),
    ];
  }
}
