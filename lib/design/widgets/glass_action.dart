import 'package:flutter/material.dart';

import '../one/glass.dart';
import '../tokens/one_tokens.dart';
import 'ow_accent.dart';
import 'system_controls.dart';

/// 框右上角的小动作钮（WEB `.overview-card__actions .ow-btn--ghost`）：
/// 玻璃底 + 发丝边 + 图标 + 短词，36dp 高，不抢正文。可点范围仍撑到 44dp。
final class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null && !busy;
    final ink = scheme.onSurface;
    final foreground = !enabled
        ? ink.withValues(alpha: 0.38)
        : selected
        ? OwAccent.green
        : ink;
    final radius = BorderRadius.circular(Glass.radiusChip);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: OneSizes.minimumTarget,
          minWidth: OneSizes.minimumTarget,
        ),
        // widthFactor: 1 让它按内容收口。不写的话 Center 会撑满 Wrap 给的
        // 全部宽度，再把按钮摆到正中——这就是「小按钮漂到框中间」的根因。
        child: Center(
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Glass.fill(scheme, dark),
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? OwAccent.green.withValues(alpha: 0.9)
                    : Glass.stroke(scheme, dark),
                width: Glass.strokeWidth,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onPressed : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Glass.space12,
                    vertical: Glass.space8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (busy)
                        SizedBox.square(
                          dimension: 14,
                          child: SystemSpinner(color: foreground),
                        )
                      else if (icon != null)
                        SystemIcon(icon!, size: 16, color: foreground),
                      if (busy || icon != null)
                        const SizedBox(width: Glass.space6),
                      // 320dp + 200% 字号时框头给不出整词的宽度，
                      // 让文字自己截断而不是把行撑爆。
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一排 [GlassActionButton]：右对齐、放不下就折行。给 [OwSection.actions] 用。
final class GlassActionRow extends StatelessWidget {
  const GlassActionRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: Glass.space6,
    runSpacing: Glass.space4,
    children: children,
  );
}

final class ChoiceChipRow extends StatelessWidget {
  const ChoiceChipRow({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<(String value, String label)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Glass.space8,
      runSpacing: Glass.space8,
      children: <Widget>[
        for (final option in options)
          SizedBox(
            height: OneSizes.minimumTarget,
            child: FilterChip(
              selected: selected == option.$1,
              label: Text(option.$2),
              onSelected: (_) => onSelected(option.$1),
              showCheckmark: false,
            ),
          ),
      ],
    );
  }
}
