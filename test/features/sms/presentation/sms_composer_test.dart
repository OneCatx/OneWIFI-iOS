import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onewifi_android/core/state/action_state.dart';
import 'package:onewifi_android/core/state/state_failure.dart';
import 'package:onewifi_android/design/theme/one_theme.dart';
import 'package:onewifi_android/features/sms/domain/sms.dart';
import 'package:onewifi_android/features/sms/presentation/widgets/sms_composer.dart';

void main() {
  testWidgets('gateway outcome=failed is not painted as a timeout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OneTheme.light(),
        home: Scaffold(
          body: SmsComposer(
            controller: TextEditingController(text: 'hello'),
            action: ActionState.failed(
              unknownOutcome: const StateFailure(
                StateFailureKind.unknownOutcome,
              ),
            ),
            lastSendResult: const SmsSendResult(
              outcome: SmsSendOutcome.failed,
              partsTotal: 1,
              partsAccepted: 0,
              retrySafe: false,
            ),
            onChanged: () {},
            onSend: () {},
            messageFieldKey: const Key('composer'),
          ),
        ),
      ),
    );

    expect(find.text('模组交互没有得到确定结果。不会自动重试。'), findsOneWidget);
    expect(find.text('请求超时或连接中断。不会自动重试。'), findsNothing);
  });
}
