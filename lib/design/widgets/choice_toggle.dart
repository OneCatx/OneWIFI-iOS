import 'package:flutter/material.dart';

import '../tokens/one_tokens.dart';
import 'glass_action.dart';

/// 协议开关：和设置里「开启 / 关闭」同一套玻璃按钮，不用系统滑块。
final class ChoiceToggle extends StatelessWidget {
  const ChoiceToggle({
    required this.value,
    required this.onChanged,
    this.onKey,
    this.offKey,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? onKey;
  final Key? offKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: OneSpacing.small,
      runSpacing: OneSpacing.small,
      children: <Widget>[
        GlassActionButton(
          key: onKey,
          icon: Icons.check_circle_outline,
          label: '开启',
          selected: value,
          onPressed: onChanged == null ? null : () => onChanged!(true),
        ),
        GlassActionButton(
          key: offKey,
          icon: Icons.cancel_outlined,
          label: '关闭',
          selected: !value,
          onPressed: onChanged == null ? null : () => onChanged!(false),
        ),
      ],
    );
  }
}
