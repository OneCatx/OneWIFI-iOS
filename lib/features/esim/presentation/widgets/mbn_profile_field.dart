import 'package:flutter/material.dart';

import '../../domain/card_policy.dart';

final class MbnProfileField extends StatelessWidget {
  const MbnProfileField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.dense = false,
    super.key,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final selected = kMbnProfileOptions.any((option) => option.value == value)
        ? value
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey<String>('mbn-profile-field:$selected'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'MBN 配置', isDense: dense),
          items: <DropdownMenuItem<String>>[
            for (final option in kMbnProfileOptions)
              DropdownMenuItem<String>(
                value: option.value,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled && onChanged != null
              ? (next) {
                  if (next != null) onChanged!(next);
                }
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          kMbnProfileHint,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}
