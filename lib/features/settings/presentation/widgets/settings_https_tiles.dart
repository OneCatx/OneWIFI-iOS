import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/choice_toggle.dart';
import '../../domain/gateway_settings.dart';

final class SettingsHttpsTiles extends StatelessWidget {
  const SettingsHttpsTiles({
    required this.https,
    required this.busy,
    required this.onChanged,
    super.key,
  });

  final HttpsSettings https;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('启用 HTTPS'),
        const SizedBox(height: OneSpacing.small),
        ChoiceToggle(
          value: https.enabled,
          onChanged: busy ? null : onChanged,
        ),
        if (https.fingerprint.isNotEmpty)
          Text(
            '指纹 ${https.fingerprint}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
