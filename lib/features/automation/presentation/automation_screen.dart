import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/automation.dart';
import '../state/automation_controller.dart';
import 'widgets/automation_run_card.dart';
import 'widgets/automation_task_card.dart';

/// 保号页（WEB「保号」侧栏页）：任务列表 + 执行记录。写入不自动重试，
/// 排队 / 运行 / 完结全部以后端持久化的 run 记录为准。刷新只靠下拉。
final class AutomationScreen extends StatefulWidget {
  const AutomationScreen({required this.controller, super.key});

  final AutomationController controller;

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

final class _AutomationScreenState extends State<AutomationScreen> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(AutomationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) _scheduleLoad();
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.workspace.status == QueryStatus.initial) {
        widget.controller.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: OneInsets.scroll(context),
        children: <Widget>[
          const OwPageHead(
            title: '保号',
            desc: '按计划发短信或探测公网 IP，保持号码活跃。写入不会自动重试。',
          ),
          const SizedBox(height: OneSpacing.medium),
          ..._content(),
        ],
      ),
    ),
  );

  List<Widget> _content() {
    final state = widget.controller.workspace;
    final value =
        state.lastGoodData ??
        (state.status == QueryStatus.empty
            ? const AutomationWorkspace(
                tasks: <AutomationTask>[],
                runs: <AutomationRun>[],
                runTotal: 0,
              )
            : null);
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return const <Widget>[
        OneStatusProgress(label: '正在读取保号任务', kind: OneProgressKind.linear),
      ];
    }
    if (value == null) {
      return const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.critical,
          title: '保号任务不可用',
          message: '任务与执行记录无法安全读取。下拉刷新再试。',
        ),
      ];
    }
    final refreshing = state.status == QueryStatus.refreshing;
    final stale = state.status == QueryStatus.failed && state.isStale;
    final enabledCount = value.tasks.where((task) => task.enabled).length;
    final failedRuns = value.runs
        .where((run) => run.status == AutomationRunStatus.failed)
        .length;
    return <Widget>[
      if (refreshing)
        const OneStatusProgress(
          label: '正在刷新保号任务',
          kind: OneProgressKind.linear,
        ),
      if (stale) ...const <Widget>[
        OneStatusHero(
          tone: OneStatusTone.attention,
          title: '显示的是上次读取的数据',
          message: '刷新没有完成，任务与记录可能已过期。',
        ),
        SizedBox(height: OneSpacing.medium),
      ],
      MetricRow(
        children: <Widget>[
          MetricCard(
            label: '任务',
            value: '${value.tasks.length}',
            sub: '$enabledCount 个已启用',
            icon: Icons.timelapse_outlined,
            tone: MetricTone.blue,
          ),
          MetricCard(
            label: '执行记录',
            value: '${value.runTotal}',
            sub: '最近 ${value.runs.length} 条已加载',
            icon: Icons.history,
            tone: MetricTone.green,
          ),
          MetricCard(
            label: '失败',
            value: '$failedRuns',
            sub: failedRuns == 0 ? '最近记录里没有失败' : '看下方记录的错误原因',
            icon: Icons.error_outline,
            tone: MetricTone.purple,
          ),
        ],
      ),
      const SizedBox(height: OneSpacing.medium),
      OwSection(
        title: '任务',
        icon: Icons.timelapse_outlined,
        tone: PlateTone.teal,
        desc: '新增与编辑请到 Web 控制台；这里只做开关、立即执行与删除。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (value.tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: OneSpacing.item),
                child: Text('还没有保号任务。'),
              )
            else
              for (final task in value.tasks) ...<Widget>[
                const SizedBox(height: OneSpacing.item),
                AutomationTaskCard(
                  task: task,
                  action: widget.controller.actionFor(task.id),
                  onToggle: (enabled) => _confirmToggle(task, enabled),
                  onRun: () => _confirmRun(task),
                  onDelete: () => _confirmDelete(task),
                ),
              ],
          ],
        ),
      ),
      const SizedBox(height: OneSpacing.medium),
      OwSection(
        title: '执行记录',
        icon: Icons.history,
        tone: PlateTone.purple,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (value.runs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: OneSpacing.item),
                child: Text('排队与完成的执行会列在这里。'),
              )
            else
              for (final run in value.runs) ...<Widget>[
                const SizedBox(height: OneSpacing.item),
                AutomationRunCard(run: run),
              ],
          ],
        ),
      ),
    ];
  }

  Future<void> _confirmToggle(AutomationTask task, bool enabled) async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: enabled ? '启用任务?' : '停用任务?',
      message: '${enabled ? '启用' : '停用'}「${task.name}」？任务的其余配置原样保留。',
      confirmLabel: enabled ? '启用' : '停用',
    );
    if (confirmed == true && mounted) {
      await widget.controller.setEnabled(task, enabled: enabled);
    }
  }

  Future<void> _confirmRun(AutomationTask task) async {
    if (task.taskType == AutomationTaskType.call) return;
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '立即执行?',
      message: '现在把「${task.name}」加入队列？结果不明时不会重试，以执行记录为准。',
      confirmLabel: '立即执行',
    );
    if (confirmed == true && mounted) await widget.controller.runNow(task);
  }

  Future<void> _confirmDelete(AutomationTask task) async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '删除任务?',
      message: '删除「${task.name}」及其执行记录？此操作不可撤销。',
      confirmLabel: '删除',
    );
    if (confirmed == true && mounted) await widget.controller.deleteTask(task);
  }
}
