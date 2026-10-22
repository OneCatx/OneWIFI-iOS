import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/glass_panel.dart';
import '../../domain/sms.dart';

final class SmsContactButton extends StatelessWidget {
  const SmsContactButton({
    required this.contact,
    required this.sourcePlate,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final SmsContact contact;

  /// 来源卡铭牌文案（卡名 / ICCID 尾号 / 设备名），空串则不画。
  final String sourcePlate;
  final bool selected;
  final VoidCallback onPressed;

  /// 头行：对方号码 ……… 来源卡铭牌（+ 未读）；正文预览一段。时间 / 本机号 /
  /// ICCID 全部不放这里，选中后会话框头再给。选中走 WEB 边缘高光。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: '短信联系人 ${contact.peerDisplay}',
      child: GlassListCard(
        semanticLabel: '短信联系人 ${contact.peerDisplay}',
        onTap: onPressed,
        selectedAccent: selected ? OwAccent.green : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CardHeadRow(
              title: contact.peerDisplay,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
              trailing: <Widget>[
                if (contact.unreadCount > 0)
                  Nameplate(
                    label: '${contact.unreadCount} 未读',
                    tone: PlateTone.blue,
                  ),
                if (sourcePlate.isNotEmpty)
                  Nameplate(label: sourcePlate, tone: PlateTone.purple),
              ],
            ),
            const SizedBox(height: OneSpacing.small),
            Text(
              contact.preview.isEmpty ? '（无内容）' : contact.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: contact.preview.isEmpty
                    ? muted
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
