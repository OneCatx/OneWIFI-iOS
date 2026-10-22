import 'package:flutter/material.dart';

import '../../../../core/state/action_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../../../design/widgets/system_controls.dart';

final class AutomationActionStatus extends StatelessWidget {
  const AutomationActionStatus({required this.action, super.key});

  final ActionState action;

  @override
  Widget build(BuildContext context) {
    final children = _content(action);
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

List<Widget> _content(ActionState action) {
  if (action.status == ActionStatus.submitting) {
    final text = action.reconciling ? '已排队 · 等待记录回来' : '提交中 · 不会自动重试';
    return <Widget>[
      const SizedBox(height: OneSpacing.item),
      Row(
        children: <Widget>[
          const SystemIcon(Icons.sync_outlined, size: 18),
          const SizedBox(width: OneSpacing.small),
          Expanded(child: Text(text)),
        ],
      ),
    ];
  }
  if (action.status == ActionStatus.succeeded) {
    return const <Widget>[SizedBox(height: OneSpacing.item), Text('已完成')];
  }
  if (action.status != ActionStatus.failed) return const <Widget>[];
  final unknown = action.isUnknownOutcome;
  final conflict = action.knownFailure?.kind.name == 'conflict';
  return <Widget>[
    const SizedBox(height: OneSpacing.item),
    OneStatusHero(
      tone: OneStatusTone.critical,
      title: unknown
          ? '结果未知'
          : conflict
          ? '任务操作冲突'
          : '任务操作失败',
      message: unknown
          ? '请求超时或断线。先下拉刷新看执行记录，再决定要不要重试。'
          : conflict
          ? '另一个操作与这条任务冲突，没有自动重试。'
          : action.knownFailure?.message ?? '操作没有完成。',
    ),
  ];
}
