import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/system_controls.dart';

final class SettingsEntryTile extends StatelessWidget {
  const SettingsEntryTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassTile(
      onTap: onTap,
      semanticLabel: title,
      child: Row(
        children: <Widget>[
          SystemIcon(icon, size: 20, color: theme.colorScheme.onSurface),
          const SizedBox(width: OneSpacing.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: OneSpacing.nano),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SystemIcon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
