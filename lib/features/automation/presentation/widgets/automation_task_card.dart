import 'package:flutter/material.dart';

import '../../../../core/format/local_time_text.dart';
import '../../../../core/state/action_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/glass_panel.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../domain/automation.dart';
import 'automation_action_status.dart';
import 'automation_labels.dart';

final class AutomationTaskCard extends StatelessWidget {
  const AutomationTaskCard({
    required this.task,
    required this.action,
    this.onToggle,
    this.onRun,
    this.onDelete,
    super.key,
  });

  final AutomationTask task;
  final ActionState action;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onRun;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final busy = action.status == ActionStatus.submitting;
    return GlassListCard(
      semanticLabel: '自动任务 ${task.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: CardHeadRow(
                  title: task.name,
                  trailing: <Widget>[
                    Nameplate(
                      label: task.enabled ? '已启用' : '已停用',
                      tone: task.enabled ? PlateTone.green : PlateTone.neutral,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OneSpacing.small),
              Semantics(
                label: task.enabled ? '停用 ${task.name}' : '启用 ${task.name}',
                child: SystemSwitch(
                  value: task.enabled,
                  onChanged: busy ? null : onToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: OneSpacing.small),
          Wrap(
            spacing: OneSpacing.small,
            runSpacing: OneSpacing.small,
            children: <Widget>[
              Nameplate(
                label: automationTaskTypeLabel(task.taskType),
                tone: task.taskType == AutomationTaskType.call
                    ? PlateTone.red
                    : PlateTone.blue,
              ),
              Nameplate(
                label: automationEnvironmentLabel(task.environment),
                tone: PlateTone.teal,
              ),
              Nameplate(label: 'ICCID ${task.profileDisplay}'),
            ],
          ),
          const SizedBox(height: OneSpacing.item),
          SoftLabelGrid(
            children: <Widget>[
              SoftLabel(
                title: '周期',
                value: task.intervalDays > 0
                    ? '每 ${task.intervalDays} 天 ${task.runTime.isEmpty ? '' : task.runTime}'
                          .trim()
                    : '—',
              ),
              SoftLabel(title: '下次执行', value: _time(task.nextRunAt)),
            ],
          ),
          const SizedBox(height: OneSpacing.item),
          GlassActionRow(
            children: <Widget>[
              if (task.taskType != AutomationTaskType.call)
                GlassActionButton(
                  icon: Icons.play_arrow_outlined,
                  label: '立即执行',
                  onPressed: busy ? null : onRun,
                ),
              GlassActionButton(
                icon: Icons.delete_outline,
                label: '删除',
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
          AutomationActionStatus(action: action),
        ],
      ),
    );
  }
}

String _time(DateTime? value) => value == null ? '—' : formatLocalMinute(value);
