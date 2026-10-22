import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../domain/call.dart';
import '../state/calls_controller.dart';
import 'call_glass.dart';

final class CallHistory {
  const CallHistory._();

  static List<VoiceCall> rowsFor(CallsController calls) => <VoiceCall>[
        ...(calls.usesNative ? calls.nativeLiveCalls : calls.liveCalls),
        ...calls.historyCalls.take(20),
      ];

  static Widget header({
    required BuildContext context,
    required CallsController calls,
    required bool empty,
  }) {
    final colors = Theme.of(context).colorScheme;
    return CallGlass(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '最近通话',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: calls.usesNative && !calls.canRefreshNative
                    ? null
                    : calls.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 40,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    calls.usesNative && calls.nativeSnapshot?.isFresh != true
                        ? '等待通话状态同步'
                        : switch (calls.calls.status) {
                            QueryStatus.loading ||
                            QueryStatus.refreshing =>
                              '正在加载通话记录…',
                            QueryStatus.failed => '暂时无法加载，请点击刷新重试',
                            _ => '还没有通话记录',
                          },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget tile({
    required BuildContext context,
    required CallsController calls,
    required VoiceCall call,
    required ValueChanged<VoiceCall> onRedial,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: colors.surface.withValues(alpha: 0.4),
        child: Icon(
          call.direction == CallDirection.incoming
              ? Icons.call_received_rounded
              : Icons.call_made_rounded,
          size: 20,
          color: call.state == CallLifecycle.failed
              ? colors.error
              : colors.onSurface,
        ),
      ),
      title: Text(
        call.number.isEmpty ? '未知号码' : call.number,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${call.directionLabel} · ${call.stateLabel}${call.startedAt == null ? '' : ' · ${_date(call.startedAt!)}'}',
      ),
      trailing: call.isLive && !calls.usesNative
          ? IconButton(
              tooltip: call.isRingingIncoming ? '接听' : '挂断',
              onPressed: () => call.isRingingIncoming
                  ? calls.answer(call)
                  : calls.hangup(call),
              icon: Icon(
                call.isRingingIncoming ? Icons.call : Icons.call_end,
              ),
            )
          : null,
      onTap: call.isLive ? null : () => onRedial(call),
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
