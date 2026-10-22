import 'package:flutter/material.dart';

import '../../../../core/format/local_time_text.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/glass_panel.dart';
import '../../domain/automation.dart';
import 'automation_labels.dart';

final class AutomationRunCard extends StatelessWidget {
  const AutomationRunCard({required this.run, super.key});

  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = automationRunStatus(run.status);
    return GlassListCard(
      semanticLabel: '自动任务运行 ${run.id}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CardHeadRow(
            title: 'Run #${run.id}',
            trailing: <Widget>[
              Nameplate(label: status.label, tone: status.tone),
            ],
          ),
          const SizedBox(height: OneSpacing.small),
          Text(
            '任务 #${run.taskId} · ${_time(run.scheduledAt)} · 尝试 ${run.attempts} 次',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (run.output.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.small),
            Text(run.output),
          ],
          if (run.error.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.small),
            Text(
              run.error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: OwAccent.ink(
                  OwAccent.red,
                  theme.brightness == Brightness.dark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _time(DateTime? value) => value == null ? '—' : formatLocalMinute(value);
