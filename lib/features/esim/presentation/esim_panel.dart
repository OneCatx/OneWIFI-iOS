import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/theme/one_theme.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../domain/esim.dart';
import '../state/esim_controller.dart';
import 'esim_edit_sheet.dart';
import 'esim_notifications_screen.dart';

/// 切卡框：照搬 WEB 的 esim-item 瓷片——点瓷片即切卡，当前卡荧光绿。
/// 「编辑 eSIM」打开 WEB 同款底栏（卡片管理 + 下载 Profile）。
final class EsimPanel extends StatefulWidget {
  const EsimPanel({
    required this.controller,
    this.header,
    this.imeiDisplay,
    this.deviceOnline = false,
    super.key,
  });
  final EsimController controller;

  /// 切卡框最上方的附加块（切卡进度）。详情页传入，单测不传。
  final Widget? header;
  final String? imeiDisplay;
  final bool deviceOnline;
  static const Key lpaFieldKey = EsimPanelLpaKey.value;

  @override
  State<EsimPanel> createState() => _EsimPanelState();
}

final class _EsimPanelState extends State<EsimPanel> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(EsimPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final inventory = widget.controller.inventory;
      final action = widget.controller.switchAction;
      final busy =
          inventory.status == QueryStatus.loading ||
          action.status == ActionStatus.submitting;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: OneSpacing.medium),
          OwSection(
            title: '切卡',
            icon: Icons.swap_horiz,
            tone: PlateTone.purple,
            semanticLabel: 'eSIM profiles',
            actions: GlassActionRow(
              children: <Widget>[
                GlassActionButton(
                  icon: Icons.edit_outlined,
                  label: '编辑 eSIM',
                  onPressed: busy ? null : _openEditor,
                ),
                GlassActionButton(
                  icon: Icons.sim_card_outlined,
                  label: '读芯片',
                  onPressed: busy ? null : _confirmReadChip,
                ),
                if (widget.controller.esimApi != null)
                  GlassActionButton(
                    icon: Icons.notifications_outlined,
                    label: '通知管理',
                    onPressed: busy ? null : _openNotifications,
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.header case final header?) ...<Widget>[
                  header,
                  const SizedBox(height: OneSpacing.item),
                ],
                ..._inventoryContent(inventory, action),
                ..._actionContent(action),
              ],
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _inventoryContent(
    QueryState<EsimInventory> state,
    ActionState action,
  ) {
    final inventory = state.lastGoodData;
    if (state.status == QueryStatus.initial ||
        state.status == QueryStatus.loading) {
      return const <Widget>[
        OneStatusProgress(label: '正在读取 eSIM 列表', kind: OneProgressKind.linear),
      ];
    }
    if (inventory == null) {
      return <Widget>[
        Text(
          state.status == QueryStatus.empty ? '没有 eSIM' : 'eSIM 列表不可用',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    if (inventory.profiles.isEmpty) {
      return <Widget>[
        Text(
          _hint(inventory.hint),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    final switching = action.status == ActionStatus.submitting;
    return <Widget>[
      for (final profile in inventory.profiles) ...<Widget>[
        _ProfileTile(
          profile: profile,
          switching: switching,
          onTap: profile.active || switching
              ? null
              : () => _confirmSwitch(profile),
        ),
        const SizedBox(height: OneSpacing.small),
      ],
    ];
  }

  List<Widget> _actionContent(ActionState action) {
    final theme = Theme.of(context);
    return switch (action.status) {
      ActionStatus.submitting => const <Widget>[
        OneStatusProgress(label: '正在切卡', kind: OneProgressKind.linear),
      ],
      ActionStatus.succeeded => <Widget>[
        const SizedBox(height: OneSpacing.item),
        Text(
          '已切换 eSIM',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      ActionStatus.failed => <Widget>[
        const SizedBox(height: OneSpacing.item),
        Text(
          action.isUnknownOutcome ? '切卡结果未知' : '切卡失败',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      ActionStatus.idle => const <Widget>[],
    };
  }

  Future<void> _openEditor() {
    return showEsimEditSheet(
      context: context,
      controller: widget.controller,
      imeiDisplay: widget.imeiDisplay,
      deviceOnline: widget.deviceOnline,
    );
  }

  void _openNotifications() {
    final api = widget.controller.esimApi;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EsimNotificationsScreen(
          deviceId: widget.controller.deviceId,
          api: api,
        ),
      ),
    );
  }

  Future<void> _confirmReadChip() async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '读取 eSIM 芯片？',
      message: '读芯片期间可能会短暂中断 VoWiFi。',
      confirmLabel: '读芯片',
    );
    if (confirmed == true && mounted) await widget.controller.readChip();
  }

  Future<void> _confirmSwitch(EsimProfile profile) async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '切换 eSIM？',
      message: '切到 ${profile.name}（${profile.iccidDisplay}）？数据和短信可能会中断。',
      confirmLabel: '切换',
    );
    if (confirmed == true && mounted) {
      await widget.controller.switchProfile(profile);
    }
  }
}

/// 一张 eSIM 瓷片：当前卡 = 荧光绿 + 辉光；点击非当前卡触发切卡。
final class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.switching,
    required this.onTap,
  });
  final EsimProfile profile;
  final bool switching;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = profile.active;
    final nameColor = active
        ? OwAccent.ink(OwAccent.green, OneTheme.isDark(theme))
        : theme.colorScheme.onSurface;
    return GlassTile(
      tone: active ? PlateTone.green : null,
      selected: active,
      onTap: onTap,
      semanticLabel: active ? '${profile.name}，当前 eSIM' : '切到 ${profile.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  profile.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: nameColor,
                  ),
                ),
              ),
              const SizedBox(width: OneSpacing.small),
              Wrap(
                spacing: OneSpacing.micro,
                runSpacing: OneSpacing.micro,
                children: <Widget>[
                  if (active)
                    const Nameplate(
                      label: '当前',
                      ready: true,
                      tone: PlateTone.green,
                    ),
                  if (switching && !active)
                    const Nameplate(label: '切换中', tone: PlateTone.blue)
                  else
                    Nameplate(
                      label: profile.state == EsimProfileState.enabled
                          ? '已启用'
                          : '已禁用',
                      tone: profile.state == EsimProfileState.enabled
                          ? PlateTone.teal
                          : PlateTone.neutral,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: OneSpacing.micro),
          Text(
            profile.provider,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: OneSpacing.micro),
          Text(
            'ICCID · ${profile.iccidDisplay}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _hint(EsimInventoryHint hint) => switch (hint) {
  EsimInventoryHint.refreshRequired => '缓存的列表是空的，读一次芯片刷新。',
  EsimInventoryHint.uimBusy => 'VoWiFi 正在占用芯片，读芯片会让它短暂暂停。',
  EsimInventoryHint.qmiUnavailable => 'eSIM 芯片通道不可用，等 VoWiFi 停止后再读芯片。',
  EsimInventoryHint.notEuicc => '没有确认到 eUICC 应用。当作实体卡之前再读一次芯片。',
  EsimInventoryHint.none => '模组没有上报已安装的 profile。',
};
