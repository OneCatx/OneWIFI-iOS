import 'package:flutter/material.dart';

import '../one/glass.dart';

/// WEB `OwPageHead`：大标题 + 淡描述，给框外层级，不跟框内正文抢字号。
final class OwPageHead extends StatelessWidget {
  const OwPageHead({required this.title, this.desc, this.actions, super.key});

  final String title;
  final String? desc;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        if (desc != null && desc!.isNotEmpty) ...<Widget>[
          const SizedBox(height: Glass.space4),
          Text(
            desc!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
            ),
          ),
        ],
        if (actions != null) ...<Widget>[
          const SizedBox(height: Glass.space8),
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: actions!),
          ),
        ],
      ],
    );
  }
}
