import 'package:flutter/material.dart';

import '../../../../app/appearance_controller.dart';
import '../../../../design/theme/one_theme.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';

final class SettingsAppearanceTiles extends StatelessWidget {
  const SettingsAppearanceTiles({required this.appearance, super.key});

  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = <(ThemeMode, String)>[
      (ThemeMode.light, '浅色'),
      (ThemeMode.dark, '深色'),
      (ThemeMode.system, '跟随系统'),
    ];
    final radius = BorderRadius.circular(OneRadii.control);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OneColors.glass(theme.brightness),
        borderRadius: radius,
        border: Border.all(
          color: OneColors.hairline(theme.brightness),
          width: OneSpacing.hairline,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < options.length; i++) ...<Widget>[
              if (i > 0)
                SizedBox(
                  width: OneSpacing.hairline,
                  height: OneSizes.minimumTarget * 0.45,
                  child: ColoredBox(
                    color: OneColors.hairline(theme.brightness),
                  ),
                ),
              Expanded(
                child: _AppearanceSegment(
                  label: options[i].$2,
                  selected: appearance.mode == options[i].$1,
                  onTap: () => appearance.setMode(options[i].$1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _AppearanceSegment extends StatelessWidget {
  const _AppearanceSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = OneTheme.isDark(theme);
    final ink = selected
        ? OwAccent.ink(OwAccent.green, dark)
        : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: OneSizes.minimumTarget,
            ),
            child: ColoredBox(
              color: selected
                  ? OwAccent.green.withValues(alpha: dark ? 0.16 : 0.10)
                  : const Color(0x00000000),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OneSpacing.micro,
                  vertical: OneSpacing.small,
                ),
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
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
