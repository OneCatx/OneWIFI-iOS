import 'package:flutter/material.dart';

import '../../../design/widgets/glass_panel.dart' as glass;

const callGreen = Color(0xFF22875A);
const callRed = Color(0xFFCF4654);

/// Blur only the major surfaces; keys and rows share their parent's frost.
final class CallGlass extends StatelessWidget {
  const CallGlass({required this.child, this.padding = const EdgeInsets.all(20), super.key});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return glass.GlassPanel(
      radius: 28,
      blur: 18,
      strong: false,
      elevate: false,
      padding: padding,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

final class CallRoundKey extends StatelessWidget {
  const CallRoundKey({required this.digit, this.letters = '', required this.onTap, this.onLongPress, super.key});
  final String digit, letters;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        label: digit == '0' && onLongPress != null ? '0，长按输入加号' : digit,
        button: true,
        enabled: onTap != null,
        excludeSemantics: true,
        child: Material(
          color: colors.surface.withValues(alpha: 0.32),
          shape: CircleBorder(side: BorderSide(color: colors.onSurface.withValues(alpha: 0.10))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              width: 72,
              height: 72,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(digit, style: TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w400, color: onTap == null ? colors.onSurface.withValues(alpha: 0.38) : colors.onSurface)),
                      if (letters.isNotEmpty) Text(letters, style: const TextStyle(fontSize: 9, letterSpacing: 1.5, height: 1.5)),
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