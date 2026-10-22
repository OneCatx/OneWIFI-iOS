import 'package:flutter/material.dart';

import '../../../../core/format/local_time_text.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../domain/sms.dart';

final class SmsMessageBubble extends StatelessWidget {
  const SmsMessageBubble({required this.message, super.key});
  final SmsMessage message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.direction == SmsDirection.outbound
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(OneRadii.panel),
        ),
        child: Padding(
          padding: OneInsets.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${message.senderDisplay} · ${_time(message.timestamp)}'),
              const SizedBox(height: OneSpacing.small),
              Text(message.body.isEmpty ? '这条短信没有可显示的文本。' : message.body),
            ],
          ),
        ),
      ),
    ),
  );
}

String _time(DateTime? value) =>
    value == null ? '时间不可用' : formatLocalMinute(value);
