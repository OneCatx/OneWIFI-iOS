import 'package:flutter/material.dart';

import '../../../../core/state/action_state.dart';
import '../../../../core/state/query_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../../../design/widgets/system_controls.dart';
import '../../domain/sms.dart';
import '../../state/sms_controller.dart';
import 'sms_message_bubble.dart';

final class SmsThreadSection extends StatelessWidget {
  const SmsThreadSection({
    required this.controller,
    required this.deleteThreadKey,
    required this.onDeleteThread,
    super.key,
  });

  final SmsController controller;
  final Key deleteThreadKey;
  final VoidCallback onDeleteThread;

  @override
  Widget build(BuildContext context) {
    final contact = controller.selectedContact!;
    final state = controller.thread;
    final thread = state.lastGoodData;
    return OwSection(
      semanticLabel: '与 ${contact.peerDisplay} 的短信会话',
      title: contact.peerDisplay,
      icon: Icons.sms_outlined,
      desc: _contactMeta(contact),
      actions: SizedBox(
        height: OneSizes.minimumTarget,
        child: OutlinedButton.icon(
          key: deleteThreadKey,
          onPressed: controller.deleteAction.status == ActionStatus.submitting
              ? null
              : onDeleteThread,
          icon: const SystemIcon(Icons.delete_outline),
          label: const Text('删除会话'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.status == QueryStatus.loading)
            const OneStatusProgress(
              label: '正在加载短信会话',
              kind: OneProgressKind.linear,
            )
          else if (thread == null || thread.messages.isEmpty)
            OneStatusHero(
              tone: OneStatusTone.attention,
              title: state.status == QueryStatus.empty ? '没有消息' : '短信会话不可用',
              message: state.status == QueryStatus.empty
                  ? '这条会话没有可显示的消息。'
                  : '所选会话无法加载。',
            )
          else ...<Widget>[
            if (thread.hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: state.status == QueryStatus.refreshing
                      ? null
                      : controller.loadEarlier,
                  icon: const SystemIcon(Icons.history),
                  label: Text(
                    state.status == QueryStatus.refreshing
                        ? '正在加载更早消息…'
                        : '加载更早消息',
                  ),
                ),
              ),
            for (final message in thread.messages) ...<Widget>[
              const SizedBox(height: OneSpacing.item),
              SmsMessageBubble(message: message),
            ],
          ],
        ],
      ),
    );
  }
}

String _contactMeta(SmsContact contact) {
  final parts = <String>[
    if (contact.deviceName.isNotEmpty) contact.deviceName,
    if (contact.localPhoneDisplay.isNotEmpty) contact.localPhoneDisplay,
    if (contact.iccidDisplay.isNotEmpty) 'ICCID ${contact.iccidDisplay}',
  ];
  return parts.join(' · ');
}
