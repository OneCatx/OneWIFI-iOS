import 'package:flutter/material.dart';

import '../one/one_status_hero.dart' as ultra;
import 'system_controls.dart';

enum OneStatusTone { healthy, attention, critical, neutral }

enum OneProgressKind { circular, linear }

final class OneStatusProgress extends StatelessWidget {
  const OneStatusProgress({required this.label, required this.kind, super.key});

  final String label;
  final OneProgressKind kind;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final indicator = reducedMotion
        ? const SystemIcon(Icons.more_horiz)
        : switch (kind) {
            OneProgressKind.circular => SystemSpinner(),
            OneProgressKind.linear => const LinearProgressIndicator(),
          };
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: indicator),
    );
  }
}

/// Maps OneWIFI tone/title/message into the Ultra status card.
final class OneStatusHero extends StatelessWidget {
  const OneStatusHero({
    required this.tone,
    required this.title,
    this.message,
    this.detail,
    this.showStages = true,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final OneStatusTone tone;
  final String title;
  final String? message;
  final String? detail;
  final bool showStages;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const List<String> stages = <String>['关闭', '处理中', '就绪'];

  @override
  Widget build(BuildContext context) {
    final state = switch (tone) {
      OneStatusTone.healthy => ultra.OneChannelState.ready,
      OneStatusTone.critical => ultra.OneChannelState.inactive,
      // Ultra "activating" is busy (spinner). OneWIFI attention is recoverable.
      OneStatusTone.attention => ultra.OneChannelState.inactive,
      OneStatusTone.neutral => ultra.OneChannelState.activating,
    };
    final pill = switch (tone) {
      OneStatusTone.healthy => '就绪',
      OneStatusTone.critical => '注意',
      OneStatusTone.attention => '注意',
      OneStatusTone.neutral => '处理中',
    };
    return ultra.OneStatusHero(
      state: state,
      title: title,
      pill: pill,
      stageLabels: showStages ? stages : null,
      subtitle: message,
      detail: detail,
      actionLabel: actionLabel,
      onAction: onAction,
      busyLabel: '处理中',
    );
  }
}
