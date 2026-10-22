import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/glass_panel.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/wifi_call_group.dart';
import '../domain/wifi_selector_catalog.dart';
import '../state/proxy_controller.dart';
import 'widgets/wifi_node_status.dart';

Future<void> showWifiNodeSheet({
  required BuildContext context,
  required ProxyController controller,
  required String groupName,
  Object? snapshotToken,
}) {
  final token = snapshotToken ?? controller.snapshotToken ?? Object();
  unawaited(controller.probeGroup(groupName, snapshotToken: token));
  return showOneGlassPopup<void>(
    context: context,
    heightFactor: 0.72,
    builder: (context) => WifiNodeSheet(
      controller: controller,
      groupName: groupName,
      snapshotToken: token,
    ),
  );
}

final class WifiNodeSheet extends StatefulWidget {
  const WifiNodeSheet({
    required this.controller,
    required this.groupName,
    this.snapshotToken,
    super.key,
  });

  static const Key rootKey = Key('proxy-node-sheet');
  static const Key probeKey = Key('proxy-node-probe');

  static Key nodeKey(String name) => ValueKey<String>('proxy-node-$name');

  final ProxyController controller;
  final String groupName;
  final Object? snapshotToken;

  @override
  State<WifiNodeSheet> createState() => _WifiNodeSheetState();
}

final class _WifiNodeSheetState extends State<WifiNodeSheet> {
  late final Object _snapshotToken =
      widget.snapshotToken ?? widget.controller.snapshotToken ?? Object();
  ProxyController get controller => widget.controller;
  String get groupName => widget.groupName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final group = _group();
        final busy = controller.selectAction.status == ActionStatus.submitting;
        final failed = controller.selectAction.status == ActionStatus.failed;
        return SizedBox(
          key: WifiNodeSheet.rootKey,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              OneInsets.scroll(context).left,
              OneSpacing.medium,
              OneInsets.scroll(context).right,
              OneSpacing.medium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        WifiSelectorCatalog.visibleGroupName(
                          group?.groupName ?? groupName,
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    GlassActionButton(
                      key: WifiNodeSheet.probeKey,
                      icon: Icons.speed,
                      label: '测速',
                      busy: controller.probing,
                      onPressed: controller.probing || group == null
                          ? null
                          : () => controller.probeGroup(
                              groupName,
                              snapshotToken: _snapshotToken,
                            ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const SystemIcon(Icons.close),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                if (group != null)
                  Text(
                    '${group.countryName} · ${group.aliveCount}/${group.totalCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (failed) ...<Widget>[
                  const SizedBox(height: OneSpacing.small),
                  Text(
                    controller.selectAction.knownFailure?.message ??
                        controller.selectAction.unknownOutcome?.message ??
                        '切换失败。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: OneSpacing.item),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: OneSpacing.item),
                    child: OneStatusProgress(
                      label: '正在切换节点',
                      kind: OneProgressKind.linear,
                    ),
                  ),
                Expanded(
                  child: group == null
                      ? const Center(child: Text('这组已经不在列表里。'))
                      : ListView.separated(
                          itemCount: group.nodes.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: OneSpacing.small),
                          itemBuilder: (context, index) {
                            final node = group.nodes[index];
                            final selected = node.name == group.now;
                            return GlassListCard(
                              key: WifiNodeSheet.nodeKey(node.name),
                              semanticLabel: node.name,
                              onTap: busy
                                  ? null
                                  : () => _select(context, node.name),
                              selectedAccent: selected ? OwAccent.green : null,
                              padding: const EdgeInsets.all(OneSpacing.item),
                              child: CardHeadRow(
                                title: WifiSelectorCatalog.stripLeadingDecor(
                                  node.name,
                                ),
                                trailing: <Widget>[
                                  if (selected)
                                    const Nameplate(label: '当前', ready: true),
                                  Nameplate(
                                    label: wifiNodeBadge(
                                      node,
                                      probing: controller.probing,
                                    ),
                                    tone: wifiNodeTone(node),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  WifiCallGroup? _group() {
    if (!controller.isSnapshotCurrent(_snapshotToken)) return null;
    final groups = controller.groups.lastGoodData;
    if (groups == null) return null;
    for (final group in groups) {
      if (group.groupName == groupName) return group;
    }
    return null;
  }

  Future<void> _select(BuildContext context, String name) async {
    final ok = await controller.selectNode(
      group: groupName,
      name: name,
      snapshotToken: _snapshotToken,
    );
    if (ok && context.mounted) Navigator.of(context).pop();
  }
}
