import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../domain/gateway_settings.dart';

final class SettingsLanguageTiles extends StatelessWidget {
  const SettingsLanguageTiles({
    required this.language,
    required this.busy,
    required this.onSelected,
    required this.languageZhKey,
    required this.languageEnKey,
    super.key,
  });

  final UiLanguage language;
  final bool busy;
  final ValueChanged<UiLanguage>? onSelected;
  final Key languageZhKey;
  final Key languageEnKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: GlassTile(
            key: languageZhKey,
            selected: language == UiLanguage.zh,
            onTap: busy || onSelected == null
                ? null
                : () => onSelected!(UiLanguage.zh),
            semanticLabel: '中文',
            child: const Center(child: Text('中文')),
          ),
        ),
        const SizedBox(width: OneSpacing.small),
        Expanded(
          child: GlassTile(
            key: languageEnKey,
            selected: language == UiLanguage.en,
            onTap: busy || onSelected == null
                ? null
                : () => onSelected!(UiLanguage.en),
            semanticLabel: 'English',
            child: const Center(child: Text('English')),
          ),
        ),
      ],
    );
  }
}
