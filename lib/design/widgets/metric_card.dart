import 'package:flutter/material.dart';

import '../one/glass.dart';
import 'glass_panel.dart';
import 'ow_accent.dart';
import 'system_controls.dart';

/// WEB `panel-title-icon--*`：框头左侧的着色图标方块。
final class PanelTitleIcon extends StatelessWidget {
  const PanelTitleIcon({required this.icon, required this.tone, super.key});

  final IconData icon;
  final PlateTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final accent = OwAccent.of(tone, theme.colorScheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(Glass.radiusChip),
        border: Border.all(
          color: accent.withValues(alpha: 0.32),
          width: Glass.strokeWidth,
        ),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: SystemIcon(icon, size: 16, color: OwAccent.ink(accent, dark)),
      ),
    );
  }
}

final class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.tone,
    super.key,
  });

  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final colors = _toneColors(theme, dark);
    return GlassListCard(
      semanticLabel: '$label $value',
      padding: const EdgeInsets.fromLTRB(
        Glass.space16,
        Glass.space16,
        Glass.space16,
        Glass.space16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.$1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.$2, width: Glass.strokeWidth),
            ),
            child: SizedBox.square(
              dimension: 40,
              child: SystemIcon(icon, size: 20, color: colors.$3),
            ),
          ),
          const SizedBox(width: Glass.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: Glass.space6),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: Glass.space6),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.78,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, Color) _toneColors(ThemeData theme, bool dark) {
    final accent = OwAccent.ofMetric(tone);
    return (
      accent.withValues(alpha: dark ? 0.16 : 0.12),
      accent.withValues(alpha: 0.34),
      OwAccent.ink(accent, dark),
    );
  }
}

final class MetricRow extends StatelessWidget {
  const MetricRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 360 ? 1 : 2;
        if (columns == 1) {
          return Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: Glass.space12),
                children[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: children[i]),
                const SizedBox(width: Glass.space12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (var i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: Glass.space12),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}
