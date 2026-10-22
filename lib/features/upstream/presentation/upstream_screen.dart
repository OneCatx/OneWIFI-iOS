import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/upstream_proxy.dart';
import '../state/upstream_controller.dart';

/// WEB「代理管理」网关出站列表的轻量下钻（非本机 Mihomo Tab）。
final class UpstreamScreen extends StatefulWidget {
  const UpstreamScreen({required this.controller, super.key});

  final UpstreamController controller;

  @override
  State<UpstreamScreen> createState() => _UpstreamScreenState();
}

final class _UpstreamScreenState extends State<UpstreamScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.items.status == QueryStatus.initial) {
        widget.controller.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.items;
        final list = state.lastGoodData ?? const <UpstreamProxy>[];
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: OneInsets.scroll(context),
            children: <Widget>[
              const OwPageHead(
                title: '网关出站代理',
                desc: 'WEB `/api/upstream-proxies`。与底栏「代理」本机 Mihomo 无关。',
              ),
              const SizedBox(height: OneSpacing.medium),
              if (state.status == QueryStatus.loading ||
                  state.status == QueryStatus.initial)
                const OneStatusProgress(
                  label: '正在读取出站代理',
                  kind: OneProgressKind.linear,
                )
              else if (state.status == QueryStatus.failed)
                Text(
                  state.failure?.message ?? '加载失败',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (list.isEmpty)
                const Text('暂无出站代理')
              else
                ...list.map(_tile),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(UpstreamProxy item) {
    final busy =
        widget.controller.busyId == item.id &&
        widget.controller.action.status == ActionStatus.submitting;
    return Padding(
      padding: const EdgeInsets.only(bottom: OneSpacing.small),
      child: GlassTile(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: OneSpacing.nano),
                  Text(
                    [
                      item.addr.isEmpty ? item.id : item.addr,
                      item.enabled ? '已启用' : '已停用',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => widget.controller.probe(item),
              child: const Text('探测'),
            ),
            TextButton(
              onPressed: busy ? null : () => widget.controller.toggle(item),
              child: Text(item.enabled ? '停用' : '启用'),
            ),
          ],
        ),
      ),
    );
  }
}
