import 'package:flutter/material.dart';

import '../one/glass.dart';
import 'glass_tile.dart';

/// WEB `SoftLabelCard`：左 11px 标签、右 13px 值，不是一排同等黑板字。
final class SoftLabel extends StatelessWidget {
  const SoftLabel({
    required this.title,
    required this.value,
    this.sub,
    this.mono = false,
    this.aux,
    this.danger = false,
    super.key,
  });

  final String title;
  final String value;
  final String? sub;
  final bool mono;
  final Widget? aux;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final valueStyle =
        (mono ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              fontFamily: mono ? 'monospace' : null,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: danger
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: Glass.space2),
        Text(value, style: valueStyle),
        if (sub != null && sub!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Glass.space2),
            child: Text(
              sub!,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ),
        if (aux != null)
          Padding(
            padding: const EdgeInsets.only(top: Glass.space4),
            child: aux!,
          ),
      ],
    );
  }
}

/// WEB 手机端 `.overview-card--sim .soft-label-grid.kv-list`：两列瓷片格，
/// 每格一个 [SoftLabel]。奇数个时最后一格独占整行，不留半边空。
final class SoftLabelGrid extends StatelessWidget {
  const SoftLabelGrid({required this.children, this.columns = 2, super.key});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 300 ? 1 : columns;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final slice = children.sublist(
            i,
            i + cols > children.length ? children.length : i + cols,
          );
          // 同一行两格等高：滚动页里 Column 高度无界，直接 stretch 会拿到无限高，
          // 所以用 IntrinsicHeight 先量出这一行的自然高度再拉平。
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var j = 0; j < slice.length; j++) ...<Widget>[
                    if (j > 0)
                      const SizedBox(width: Glass.space8 + Glass.space2),
                    Expanded(child: GlassTile(child: slice[j])),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: Glass.space8 + Glass.space2),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}
