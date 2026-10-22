import 'package:flutter/material.dart';

import '../../../../core/state/query_state.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../../devices/state/device_list_controller.dart';
import '../../domain/sms.dart';
import '../../state/sms_controller.dart';
import 'sms_contact_button.dart';

final class SmsContactsSection extends StatelessWidget {
  const SmsContactsSection({
    required this.visible,
    required this.controller,
    required this.devices,
    super.key,
  });

  final List<SmsContact> visible;
  final SmsController controller;
  final DeviceListController? devices;

  @override
  Widget build(BuildContext context) {
    final state = controller.contacts;
    final contacts = state.lastGoodData;
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return const OneStatusProgress(
        label: '正在加载短信联系人',
        kind: OneProgressKind.linear,
      );
    }
    if (contacts == null || contacts.isEmpty) {
      return OneStatusHero(
        tone: OneStatusTone.attention,
        title: state.status == QueryStatus.empty ? '没有短信联系人' : '短信联系人不可用',
        message: state.status == QueryStatus.empty
            ? '模组收到或发出短信后，会话会出现在这里。'
            : '联系人数据无法安全加载。',
      );
    }
    return OwSection(
      semanticLabel: '短信联系人',
      title: '联系人',
      icon: Icons.forum_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.status == QueryStatus.refreshing)
            const OneStatusProgress(
              label: '正在刷新短信联系人',
              kind: OneProgressKind.linear,
            ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: OneSpacing.item),
              child: Text('该模组下没有联系人。'),
            )
          else
            for (final contact in visible) ...<Widget>[
              const SizedBox(height: OneSpacing.item),
              SmsContactButton(
                contact: contact,
                sourcePlate: _sourcePlate(contact),
                selected:
                    controller.selectedContact?.watchKey == contact.watchKey,
                onPressed: () => controller.selectContact(contact),
              ),
            ],
        ],
      ),
    );
  }

  /// 联系人卡右上角铭牌 = 这条会话「走的是哪张卡」。`/api/sms/contacts` 只带
  /// ICCID 与设备名，卡名要从设备列表已缓存的 eUICC 总览里按 ICCID 尾号反查：
  /// 卡名 → ICCID 尾号 → 设备名，逐级回退，绝不为此再打一次 UIM。
  static String sourcePlate(SmsContact contact, DeviceListController? devices) {
    if (devices != null && contact.iccidDisplay.isNotEmpty) {
      final deviceId = devices.deviceIdNamed(contact.deviceName);
      final name = deviceId == null
          ? null
          : devices.cardNameFor(deviceId, contact.iccidDisplay);
      if (name != null && name.isNotEmpty) return name;
    }
    if (contact.iccidDisplay.isNotEmpty) return '卡 ${contact.iccidDisplay}';
    return contact.deviceName;
  }

  String _sourcePlate(SmsContact contact) => sourcePlate(contact, devices);

  static Widget sectionHeader({required bool refreshing}) {
    return OwSection(
      semanticLabel: '短信联系人',
      title: '联系人',
      icon: Icons.forum_outlined,
      child: refreshing
          ? const OneStatusProgress(
              label: '正在刷新短信联系人',
              kind: OneProgressKind.linear,
            )
          : const SizedBox.shrink(),
    );
  }
}
