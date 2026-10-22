import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/gateway_extension.dart';
import '../state/extensions_controller.dart';

/// WEB「扩展」页的轻量下钻：列表 / URL 安装 / 启停 / 删除。入口只在设置壳。
final class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({required this.controller, super.key});

  final ExtensionsController controller;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

final class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _sha = TextEditingController();

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
  void dispose() {
    _url.dispose();
    _sha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.items;
        final busy = widget.controller.action.status == ActionStatus.submitting;
        final list = state.lastGoodData ?? const <GatewayExtension>[];
        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: OneInsets.scroll(context),
            children: <Widget>[
              const OwPageHead(
                title: '扩展',
                desc: '网关插件列表。从 HTTPS 地址安装，或启停 / 卸载已有扩展。',
              ),
              const SizedBox(height: OneSpacing.medium),
              OwSection(
                title: '从 URL 安装',
                icon: Icons.download_outlined,
                tone: PlateTone.blue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'HTTPS 地址',
                        hintText: 'https://…/plugin.zip',
                      ),
                      enabled: !busy,
                    ),
                    const SizedBox(height: OneSpacing.small),
                    TextField(
                      controller: _sha,
                      decoration: const InputDecoration(
                        labelText: 'SHA256（可选）',
                      ),
                      enabled: !busy,
                    ),
                    const SizedBox(height: OneSpacing.item),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await widget.controller.installFromUrl(
                                _url.text,
                                sha256: _sha.text,
                              );
                              if (!mounted) return;
                              if (widget.controller.action.status ==
                                  ActionStatus.succeeded) {
                                _url.clear();
                                _sha.clear();
                              }
                            },
                      child: const Text('安装'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OneSpacing.medium),
              if (state.status == QueryStatus.loading ||
                  state.status == QueryStatus.initial)
                const OneStatusProgress(
                  label: '正在读取扩展',
                  kind: OneProgressKind.linear,
                )
              else if (state.status == QueryStatus.failed)
                Text(
                  state.failure?.message ?? '加载失败',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (list.isEmpty)
                const Text('暂无扩展')
              else
                ...list.map(_tile),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(GatewayExtension item) {
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
                      item.id,
                      if (item.version.isNotEmpty) item.version,
                      item.enabled ? '已启用' : '已停用',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => widget.controller.toggle(item),
              child: Text(item.enabled ? '停用' : '启用'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await showOneGlassDialog(
                        context: context,
                        title: '删除扩展？',
                        message: '删除「${item.name}」。',
                        confirmLabel: '删除',
                      );
                      if (ok == true) await widget.controller.remove(item);
                    },
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}
