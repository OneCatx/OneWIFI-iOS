import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/export_proxy.dart';
import '../state/export_proxy_controller.dart';

/// WEB「导出代理」轻量下钻；需网关开发者模式，否则显示后端错误。
final class ExportProxyScreen extends StatefulWidget {
  const ExportProxyScreen({required this.controller, super.key});

  final ExportProxyController controller;

  @override
  State<ExportProxyScreen> createState() => _ExportProxyScreenState();
}

final class _ExportProxyScreenState extends State<ExportProxyScreen> {
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
        final list = state.lastGoodData ?? const <ExportProxyConfig>[];
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: OneInsets.scroll(context),
            children: <Widget>[
              const OwPageHead(
                title: '导出代理',
                desc: 'WEB `/api/export-proxies`（开发者模式）。列表与运行状态只读。',
              ),
              const SizedBox(height: OneSpacing.medium),
              if (state.status == QueryStatus.loading ||
                  state.status == QueryStatus.initial)
                const OneStatusProgress(
                  label: '正在读取导出代理',
                  kind: OneProgressKind.linear,
                )
              else if (state.status == QueryStatus.failed)
                Text(
                  state.failure?.message ?? '加载失败',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (list.isEmpty)
                const Text('暂无导出代理配置')
              else
                ...list.map(_tile),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(ExportProxyConfig item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OneSpacing.small),
      child: GlassTile(
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
                '${item.mode}://${item.listenHost}:${item.listenPort}',
                if (item.deviceId.isNotEmpty) '设备 ${item.deviceId}',
                item.enabled ? '已启用' : '已停用',
                item.running ? '运行中' : '未运行',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
