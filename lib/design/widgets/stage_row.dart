import 'package:flutter/material.dart';

import '../one/glass.dart';
import 'ow_accent.dart';

/// WEB `stage-row` / `stage-bar`：一排等宽阶段条，条下小字标签。
///
/// 就绪 → 绿色带辉光；进行中 → 琥珀；失败 → 红；未到 → 玻璃描边空条。
/// 用在运行状态框的「当前进度」（SIM → Access → Tunnel → IMS → 卡策略）。
enum StageState { pending, active, ready, failed }

final class StageRow extends StatelessWidget {
  const StageRow({required this.stages, this.semanticLabel, super.key});

  final List<(String label, StageState state)> stages;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final scheme = theme.colorScheme;
    return Semantics(
      label: semanticLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < stages.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: Glass.space6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _StageBar(state: stages[i].$2),
                  const SizedBox(height: Glass.space6),
                  Text(
                    stages[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: switch (stages[i].$2) {
                        StageState.ready => OwAccent.ink(OwAccent.green, dark),
                        StageState.active => OwAccent.ink(OwAccent.blue, dark),
                        StageState.failed => OwAccent.ink(OwAccent.red, dark),
                        StageState.pending =>
                          scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      },
                      fontWeight: stages[i].$2 == StageState.pending
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _StageBar extends StatelessWidget {
  const _StageBar({required this.state});

  final StageState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final scheme = theme.colorScheme;
    final accent = switch (state) {
      StageState.ready => OwAccent.green,
      StageState.active => OwAccent.blue,
      StageState.failed => OwAccent.red,
      StageState.pending => null,
    };
    return Container(
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color:
            accent?.withValues(alpha: dark ? 0.92 : 0.86) ??
            scheme.onSurface.withValues(alpha: dark ? 0.10 : 0.07),
        border: accent == null
            ? Border.all(
                color: Glass.stroke(scheme, dark),
                width: Glass.strokeWidth,
              )
            : null,
        boxShadow: state == StageState.ready
            ? OwAccent.plateShadow(OwAccent.green)
            : null,
      ),
    );
  }
}
