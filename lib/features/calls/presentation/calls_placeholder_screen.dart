import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';

/// 通话页占位：先占底栏，功能还没接。
final class CallsPlaceholderScreen extends StatelessWidget {
  const CallsPlaceholderScreen({super.key});

  static const Key rootKey = Key('calls-placeholder-screen');

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: rootKey,
      padding: OneInsets.scroll(context),
      children: const <Widget>[
        OwPageHead(title: '通话', desc: '这一页先占着，后面再接 WiFi Call。'),
        SizedBox(height: OneSpacing.item),
        OneStatusHero(
          tone: OneStatusTone.attention,
          title: '通话还没接上',
          message: '先去代理页选国家节点。通话能力下一轮再做。',
          showStages: false,
        ),
      ],
    );
  }
}
