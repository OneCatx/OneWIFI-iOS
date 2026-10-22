import 'package:flutter/material.dart';

import '../../../../core/state/action_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../domain/sms.dart';

final class SmsComposer extends StatelessWidget {
  const SmsComposer({
    required this.controller,
    required this.action,
    required this.lastSendResult,
    required this.onChanged,
    required this.onSend,
    required this.messageFieldKey,
    super.key,
  });

  final TextEditingController controller;
  final ActionState action;
  final SmsSendResult? lastSendResult;
  final VoidCallback onChanged;
  final VoidCallback? onSend;
  final Key messageFieldKey;

  @override
  Widget build(BuildContext context) {
    final submitting = action.status == ActionStatus.submitting;
    return OwSection(
      semanticLabel: '撰写短信',
      title: '回复',
      icon: Icons.edit_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: OneSpacing.item),
          TextField(
            key: messageFieldKey,
            controller: controller,
            enabled: !submitting,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '输入短信内容',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: OneSpacing.item),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: submitting || controller.text.trim().isEmpty
                  ? null
                  : onSend,
              icon: const SystemIcon(Icons.send_outlined),
              label: Text(submitting ? '发送中…' : '发送'),
            ),
          ),
          if (submitting)
            const OneStatusProgress(
              label: '正在发送短信，不会自动重试',
              kind: OneProgressKind.linear,
            ),
          ..._sendOutcome(action, lastSendResult),
        ],
      ),
    );
  }
}

List<Widget> _sendOutcome(ActionState action, SmsSendResult? result) {
  if (result?.outcome == SmsSendOutcome.failed) {
    return <Widget>[
      const SizedBox(height: OneSpacing.item),
      const OneStatusHero(
        tone: OneStatusTone.critical,
        title: '短信结果未知',
        message: '模组交互没有得到确定结果。不会自动重试。',
      ),
    ];
  }
  if (action.status == ActionStatus.succeeded && result != null) {
    final (title, message, tone) = switch (result.outcome) {
      SmsSendOutcome.delivered => ('短信已送达', '后端已确认送达。', OneStatusTone.healthy),
      SmsSendOutcome.acceptedUnconfirmed => (
        '已受理，送达未确认',
        '全部分段已受理。等待送达证据期间不会自动重发。',
        OneStatusTone.attention,
      ),
      SmsSendOutcome.partial => (
        '短信部分受理',
        '${result.partsTotal} 个分段中已受理 ${result.partsAccepted} 个。不要整条重发。',
        OneStatusTone.attention,
      ),
      SmsSendOutcome.failed => (
        '短信结果未知',
        '模组交互没有得到确定结果。不会自动重试。',
        OneStatusTone.critical,
      ),
    };
    return <Widget>[
      const SizedBox(height: OneSpacing.item),
      OneStatusHero(tone: tone, title: title, message: message),
    ];
  }
  if (action.status != ActionStatus.failed) return const <Widget>[];
  final unknown = action.isUnknownOutcome;
  return <Widget>[
    const SizedBox(height: OneSpacing.item),
    OneStatusHero(
      tone: OneStatusTone.critical,
      title: unknown ? '短信结果未知' : '短信未发送',
      message: unknown
          ? '请求超时或连接中断。不会自动重试。'
          : action.knownFailure?.kind.name == 'conflict'
          ? '另一项短信操作正在进行，请稍后再试。'
          : '后端在确认提交前拒绝了这条短信。',
    ),
  ];
}
