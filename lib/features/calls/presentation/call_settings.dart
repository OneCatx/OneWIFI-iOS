import 'package:flutter/material.dart';

import '../../../design/widgets/glass_dialog.dart';
import '../state/calls_controller.dart';

final class NativeCallSettingsButton extends StatelessWidget {
  const NativeCallSettingsButton({required this.calls, super.key});
  final CallsController calls;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '通话设置',
    icon: const Icon(Icons.tune_rounded),
    onPressed: () => showOneGlassPopup<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: calls,
        builder: (context, _) {
          final state = calls.nativeSnapshot;
          final configured = state?.status == 'configured';
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('通话设置', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.phone_iphone_rounded),
              title: Text('系统来电 · CallKit'),
              subtitle: Text('已建立的通话交由 iOS 管理。未接入后台来电推送，应用挂起或退出后不保证收到新来电。'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mic_none_rounded),
              title: const Text('通话权限'),
              subtitle: Text(state?.permissions['microphone'] == true ? '麦克风已允许' : '需要麦克风权限；已拒绝时请前往应用设置'),
              enabled: configured && !calls.nativeBusy,
              onTap: calls.requestPermissions,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('刷新通话状态'),
              subtitle: Text(calls.nativeStatusLabel),
              enabled: calls.canRefreshNative,
              onTap: calls.refresh,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('应用设置'),
              enabled: configured && !calls.nativeBusy,
              onTap: calls.openAppSettings,
            ),
            if (calls.notice.isNotEmpty) Text(calls.notice),
            if (calls.nativeEventDiagnostic.isNotEmpty) Text(calls.nativeEventDiagnostic),
            if (state?.eventDiagnostic.isNotEmpty == true) SelectableText(state!.eventDiagnostic),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ]);
        },
      ),
    ),
  );
}