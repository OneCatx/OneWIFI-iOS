import 'package:flutter/material.dart';

import '../state/calls_controller.dart';
import 'call_glass.dart';

/// Connection and failure diagnostics only. CallKit owns the live call UI.
final class NativeCallPanel extends StatelessWidget {
  const NativeCallPanel({required this.calls, super.key});
  final CallsController calls;

  @override
  Widget build(BuildContext context) {
    final state = calls.nativeSnapshot;
    return Column(key: const Key('native-call-panel'), children: [
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, size: 6, color: state?.canReceiveCalls == true ? callGreen : Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(child: Semantics(liveRegion: true, child: Text(calls.nativeStatusLabel, style: Theme.of(context).textTheme.bodySmall))),
        ],
      )),
      if (calls.nativeEventDiagnostic.isNotEmpty ||
          state?.eventDiagnostic.isNotEmpty == true ||
          const {'failed', 'offline', 'stale', 'stopped', 'unavailable'}.contains(state?.eventStatus))
        CallGlass(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(calls.nativeEventDiagnostic),
          if (state?.eventDiagnostic.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            const Text('连接诊断（请将下方内容截图反馈）'),
            SelectableText(state!.eventDiagnostic, key: const Key('native-tls-diagnostic'), style: Theme.of(context).textTheme.bodySmall),
          ],
          TextButton.icon(key: const Key('native-refresh'), onPressed: calls.canRefreshNative ? calls.refresh : null,
            icon: const Icon(Icons.refresh), label: const Text('刷新通话状态')),
        ])),
      if (state?.systemDiagnostic.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CallGlass(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('系统通话诊断（最近一次失败，请截图反馈）'),
              const SizedBox(height: 8),
              SelectableText(state!.systemDiagnostic,
                key: const Key('native-system-diagnostic'),
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              const Text('连接就绪不代表系统通话可用；此记录会保留到退出登录或重新配置。'),
            ]),
          ),
        ),
      if (state?.audioDiagnostic.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CallGlass(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('音频诊断（最近一次失败，请截图反馈）'),
              const SizedBox(height: 8),
              SelectableText(state!.audioDiagnostic,
                key: const Key('native-audio-diagnostic'),
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              const Text('tx 为发送端，rx 为播放端；Dropped 为清理的过时音频帧，不是断线次数。'),
            ]),
          ),
        ),
    ]);
  }
}