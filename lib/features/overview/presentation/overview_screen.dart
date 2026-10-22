import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/glass_panel.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../state/overview_controller.dart';
import 'widgets/overview_host_metrics.dart';
import 'widgets/overview_host_panel.dart';
import 'widgets/overview_usage_panel.dart';

final class OverviewScreen extends StatefulWidget {
  const OverviewScreen({required this.controller, super.key});

  final OverviewController controller;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

final class _OverviewScreenState extends State<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  void didUpdateWidget(OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: OneInsets.scroll(context),
            children: _content(context, state),
          ),
        );
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    QueryState<OverviewSnapshot> state,
  ) {
    final snapshot = state.lastGoodData;
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return <Widget>[
        const OneStatusHero(
          tone: OneStatusTone.neutral,
          title: '正在加载概览',
          message: '正在检查主机与设备健康。',
          showStages: false,
        ),
        const SizedBox(height: OneSpacing.medium),
        const Center(
          child: OneStatusProgress(
            label: '正在加载概览',
            kind: OneProgressKind.circular,
          ),
        ),
      ];
    }
    if (state.status == QueryStatus.empty) {
      return <Widget>[
        const OneStatusHero(
          tone: OneStatusTone.attention,
          title: '没有概览数据',
          message: '主机与设备都没有上报活动。',
          detail: '下拉刷新。',
          showStages: false,
        ),
      ];
    }
    if (snapshot == null) {
      return <Widget>[
        const OneStatusHero(
          tone: OneStatusTone.critical,
          title: '概览不可用',
          message: '服务无法提供主机或设备数据。',
          showStages: false,
        ),
      ];
    }

    final partial =
        snapshot.hostFailure != null || snapshot.devicesFailure != null;
    final refreshing = state.status == QueryStatus.refreshing;
    final devices = snapshot.devices;
    final healthyDevices =
        devices?.where((device) => device.healthy).length ?? 0;
    final allHealthy = devices != null && healthyDevices == devices.length;
    final hero = partial
        ? const OneStatusHero(
            tone: OneStatusTone.attention,
            title: '部分概览数据不可用',
            message: '失败的区块恢复期间，已显示的数据会保留。',
            showStages: false,
          )
        : allHealthy
        ? const OneStatusHero(
            tone: OneStatusTone.healthy,
            title: 'OneWIFI',
            showStages: false,
          )
        : OneStatusHero(
            tone: OneStatusTone.attention,
            title: 'OneWIFI 概览',
            message: '主机在线 · ${devices?.length ?? 0} 台设备中 $healthyDevices 台健康',
            showStages: false,
          );
    return <Widget>[
      hero,
      if (refreshing) ...const <Widget>[
        SizedBox(height: OneSpacing.item),
        OneStatusProgress(label: '正在刷新概览', kind: OneProgressKind.linear),
      ],
      if (snapshot.host != null) ...<Widget>[
        const SizedBox(height: OneSpacing.medium),
        OverviewHostMetrics(host: snapshot.host!),
        const SizedBox(height: OneSpacing.medium),
        OverviewHostPanel(host: snapshot.host!, stale: snapshot.hostStale),
        const SizedBox(height: OneSpacing.medium),
        OverviewUsagePanel(host: snapshot.host!, stale: snapshot.hostStale),
      ],
      if (snapshot.hostFailure != null &&
          snapshot.host == null) ...const <Widget>[
        SizedBox(height: OneSpacing.medium),
        _SectionFailure(label: '主机数据不可用。'),
      ],
    ];
  }
}

final class _SectionFailure extends StatelessWidget {
  const _SectionFailure({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassListCard(semanticLabel: label, child: Text(label));
  }
}
