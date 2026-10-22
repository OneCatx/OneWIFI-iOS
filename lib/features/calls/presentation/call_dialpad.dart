import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/state/action_state.dart';
import '../domain/call.dart';
import '../state/calls_controller.dart';
import 'call_glass.dart';

final class CallDialpad extends StatelessWidget {
  const CallDialpad({required this.calls, required this.field, super.key});
  final CallsController calls;
  final TextEditingController field;

  @override
  Widget build(BuildContext context) {
    final busy = calls.nativeBusy || calls.dialAction.status == ActionStatus.submitting;
    final enabled = validDialNumber(calls.dialNumber) && !busy &&
        (calls.usesNative ? calls.canDialNative : calls.deviceId != null);
    return CallGlass(
      child: Column(
        children: [
          TextField(
            key: const Key('calls-dial-field'),
            controller: field,
            onChanged: calls.setDialNumber,
            keyboardType: TextInputType.none,
            textAlign: TextAlign.center,
            autocorrect: false,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 1.2),
            decoration: const InputDecoration(
              hintText: '输入号码', border: InputBorder.none,
              enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
              filled: false, contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              children: [
                for (var row = 0; row < 4; row++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      for (var col = 0; col < 3; col++)
                        Expanded(child: CallRoundKey(
                          digit: '123456789*0#'[row * 3 + col],
                          letters: const ['', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ', '', '+', ''][row * 3 + col],
                          onTap: () {
                            HapticFeedback.selectionClick();
                            calls.appendKey('123456789*0#'[row * 3 + col]);
                          },
                          onLongPress: row == 3 && col == 1 ? () => calls.appendKey('+') : null,
                        )),
                    ]),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: SizedBox()),
                  Expanded(child: Center(child: SizedBox(
                    width: 76, height: 64,
                    child: FilledButton(
                      key: const Key('calls-dial-button'),
                      style: FilledButton.styleFrom(backgroundColor: callGreen, foregroundColor: Colors.white, padding: EdgeInsets.zero, shape: const StadiumBorder()),
                      onPressed: enabled ? calls.dial : null,
                      child: busy
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.call_rounded, size: 30, semanticLabel: '拨出'),
                    ),
                  ))),
                  Expanded(child: Center(child: IconButton(
                    tooltip: '退格，长按清空',
                    onPressed: calls.dialNumber.isEmpty ? null : calls.backspace,
                    onLongPress: () => calls.setDialNumber(''),
                    icon: const Icon(Icons.backspace_outlined),
                  ))),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}