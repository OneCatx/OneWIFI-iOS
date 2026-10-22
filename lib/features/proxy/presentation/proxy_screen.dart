import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../data/wifi_pin_store.dart';
import '../domain/wifi_call_connection.dart';
import '../domain/wifi_call_group.dart';
import '../domain/wifi_connection_catalog.dart';
import '../domain/wifi_selector_catalog.dart';
import '../state/proxy_controller.dart';
import 'widgets/wifi_call_connection_row.dart';
import 'widgets/wifi_call_country_card.dart';
import 'wifi_connection_sheet.dart';
import 'wifi_country_sheet.dart';
import 'wifi_node_sheet.dart';

final class ProxyScreen extends StatefulWidget {
  const ProxyScreen({required this.controller, super.key});

  static const Key rootKey = Key('proxy-screen');
  static const Key gridKey = Key('proxy-country-grid');
  static const Key connectionsKey = Key('proxy-connections');
  static const Key moreConnectionsKey = Key('proxy-connections-more');
  static const Key plusKey = Key('proxy-country-plus');
  static const Key probeKey = Key('proxy-probe-currents');

  static Key countryKey(String groupName) =>
      ValueKey<String>('proxy-country-$groupName');

  final ProxyController controller;

  @override
  State<ProxyScreen> createState() => _ProxyScreenState();
}

final class _ProxyScreenState extends State<ProxyScreen> {
  final WifiPinStore _pinsStore = WifiPinStore();
  List<String> _pins = List<String>.of(WifiSelectorCatalog.pinnedCountryOrder);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
    _loadPins();
  }

  Future<void> _loadPins() async {
    final pins = await _pinsStore.read();
    if (!mounted) return;
    setState(() => _pins = pins);
  }

  Future<void> _addPin(String code) async {
    final next = List<String>.of(_pins);
    final canonical = code.toUpperCase() == 'UK' ? 'GB' : code.toUpperCase();
    if (!next.contains(canonical)) next.add(canonical);
    setState(() => _pins = next);
    await _pinsStore.write(next);
  }

  Future<void> _removePin(String code) async {
    final canonical = code.toUpperCase() == 'UK' ? 'GB' : code.toUpperCase();
    final next = <String>[
      for (final pin in _pins)
        if (pin != canonical) pin,
    ];
    setState(() => _pins = next);
    await _pinsStore.write(next);
  }

  @override
  void didUpdateWidget(ProxyScreen oldWidget) {
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
        final state = widget.controller.groups;
        final pad = OneInsets.scroll(context);
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: CustomScrollView(
            key: ProxyScreen.rootKey,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pad.left,
                  pad.top,
                  pad.right,
                  OneSpacing.item,
                ),
                sliver: const SliverToBoxAdapter(
                  child: OwPageHead(title: '代理', desc: '上面看当前连接，下面点国家换节点。'),
                ),
              ),
              ..._body(context, state, pad),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(
    BuildContext context,
    QueryState<List<WifiCallGroup>> state,
    EdgeInsets pad,
  ) {
    final groups = state.lastGoodData;
    if (widget.controller.needsConnection) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
          sliver: const SliverToBoxAdapter(
            child: OneStatusHero(
              tone: OneStatusTone.attention,
              title: '还没连 Mihomo',
              message: '先到设置里填主机和端口，点连接。连好了再回来选节点。',
              showStages: false,
            ),
          ),
        ),
      ];
    }
    if ((state.status == QueryStatus.initial ||
            state.status == QueryStatus.loading) &&
        groups == null) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
          sliver: const SliverToBoxAdapter(
            child: Column(
              children: <Widget>[
                OneStatusHero(
                  tone: OneStatusTone.neutral,
                  title: '正在读取节点',
                  message: '正在向 Mihomo 拉取 XX-WIFI 组。',
                  showStages: false,
                ),
                SizedBox(height: OneSpacing.medium),
                Center(
                  child: OneStatusProgress(
                    label: '正在读取节点',
                    kind: OneProgressKind.circular,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (state.status == QueryStatus.empty && groups == null) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
          sliver: const SliverToBoxAdapter(
            child: OneStatusHero(
              tone: OneStatusTone.attention,
              title: '没有 XX-WIFI 组',
              message: 'Mihomo 里找不到 HK-WIFI、US-WIFI 这类国家组。',
              detail: '下拉刷新。',
              showStages: false,
            ),
          ),
        ),
      ];
    }
    if (groups == null) {
      return <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
          sliver: SliverToBoxAdapter(
            child: OneStatusHero(
              tone: OneStatusTone.critical,
              title: '连不上 Mihomo',
              message: state.failure?.message ?? '无法读取代理节点。',
              detail: '到设置里核对 Mihomo 地址。',
              showStages: false,
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _connectionsSection(context),
              const SizedBox(height: OneSpacing.medium),
              _countriesSection(context, groups),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _connectionsSection(BuildContext context) {
    final rows =
        widget.controller.connections.lastGoodData ??
        const <WifiCallConnection>[];
    final preview = WifiConnectionCatalog.previewOf(rows);
    final sheet = WifiConnectionCatalog.sheetOf(rows);
    return OwSection(
      key: ProxyScreen.connectionsKey,
      title: '连接',
      icon: Icons.hub_outlined,
      tone: PlateTone.teal,
      desc: '当前 WIFI 会话。',
      actions: GlassActionButton(
        key: ProxyScreen.moreConnectionsKey,
        icon: Icons.more_horiz,
        label: '更多',
        onPressed: () =>
            showWifiConnectionSheet(context: context, connections: sheet),
      ),
      child: preview.isEmpty
          ? Text('当前没有会话。', style: Theme.of(context).textTheme.bodySmall)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const WifiCallConnectionHeader(),
                const SizedBox(height: OneSpacing.micro),
                for (var i = 0; i < preview.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  WifiCallConnectionRow(
                    key: ValueKey<String>('proxy-connection-${preview[i].id}'),
                    connection: preview[i],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _countriesSection(BuildContext context, List<WifiCallGroup> groups) {
    final snapshotToken = widget.controller.snapshotToken;
    final pinned = WifiSelectorCatalog.pinnedBy(groups, _pins);
    final more = WifiSelectorCatalog.moreBy(groups, _pins);
    final tiles = <Widget>[
      for (final group in pinned)
        WifiCallCountryCard(
          key: ProxyScreen.countryKey(group.groupName),
          group: group,
          probing: widget.controller.probing,
          onRemove: () => _removePin(group.countryCode),
          onTap: () => showWifiNodeSheet(
            context: context,
            controller: widget.controller,
            groupName: group.groupName,
            snapshotToken: snapshotToken,
          ),
        ),
      WifiCallPlusCard(
        key: ProxyScreen.plusKey,
        onTap: () => showWifiCountrySheet(
          context: context,
          controller: widget.controller,
          groups: more,
          onPick: (group) => _addPin(group.countryCode),
        ),
      ),
    ];
    return OwSection(
      title: '节点',
      icon: Icons.public_outlined,
      tone: PlateTone.blue,
      desc: '一级菜单可以加，也可以移出。加号里选国家放上来。',
      actions: GlassActionButton(
        key: ProxyScreen.probeKey,
        icon: Icons.speed,
        label: '测速',
        busy: widget.controller.probing,
        onPressed: widget.controller.probing
            ? null
            : () => widget.controller.probeCurrents(
                countryCodes: _pins,
                snapshotToken: snapshotToken,
              ),
      ),
      child: Builder(
        builder: (context) {
          final rows = (tiles.length + 1) ~/ 2;
          final gridHeight = rows == 0
              ? 0.0
              : rows * WifiCallCountryCard.extent +
                  (rows - 1) * OneSpacing.item;
          return SizedBox(
            height: gridHeight,
            child: GridView.builder(
              key: ProxyScreen.gridKey,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: OneSpacing.item,
                crossAxisSpacing: OneSpacing.item,
                mainAxisExtent: WifiCallCountryCard.extent,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) => tiles[index],
            ),
          );
        },
      ),
    );
  }
}
