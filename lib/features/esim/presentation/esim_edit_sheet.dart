import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/state/action_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/card_policy.dart';
import '../domain/esim.dart';
import '../domain/euicc_hardware.dart';
import '../domain/lpa_smdp_preview.dart';
import '../state/esim_controller.dart';
import 'widgets/esim_profile_editor.dart';

Future<void> showEsimEditSheet({
  required BuildContext context,
  required EsimController controller,
  String? imeiDisplay,
  bool deviceOnline = false,
  LpaSmdpCatalog? previewCatalog,
}) {
  return showOneGlassPopup<void>(
    context: context,
    heightFactor: 0.86,
    builder: (context) => EsimEditSheet(
      controller: controller,
      imeiDisplay: imeiDisplay,
      deviceOnline: deviceOnline,
      previewCatalog: previewCatalog,
    ),
  );
}

/// WEB `EsimEditDialog`：卡片管理（改名 / 启用停用 / 删除 / 卡策略）+ 下载 Profile。
final class EsimEditSheet extends StatefulWidget {
  const EsimEditSheet({
    required this.controller,
    this.imeiDisplay,
    this.deviceOnline = false,
    this.previewCatalog,
    super.key,
  });

  final EsimController controller;
  final String? imeiDisplay;
  final bool deviceOnline;
  final LpaSmdpCatalog? previewCatalog;

  @override
  State<EsimEditSheet> createState() => _EsimEditSheetState();
}

enum _EditTab { profiles, download }

final class _EsimEditSheetState extends State<EsimEditSheet> {
  _EditTab _tab = _EditTab.profiles;
  final TextEditingController _lpa = TextEditingController();
  final Map<EsimSwitchTarget, TextEditingController> _names =
      <EsimSwitchTarget, TextEditingController>{};
  final Map<EsimSwitchTarget, CardPolicy> _policies =
      <EsimSwitchTarget, CardPolicy>{};
  final Set<EsimSwitchTarget> _policyLoading = <EsimSwitchTarget>{};
  String _feedback = '';
  bool _feedbackError = false;
  bool _feedbackUnknown = false;
  int _feedbackVersion = 0;
  int _policyVersion = 0;
  LpaSmdpCatalog? _previewCatalog;

  EsimController get _controller => widget.controller;

  bool get _mutating =>
      _controller.mutateAction.status == ActionStatus.submitting ||
      _controller.switchAction.status == ActionStatus.submitting ||
      _controller.policyAction.status == ActionStatus.submitting ||
      _controller.downloadAction.status == ActionStatus.submitting;

  @override
  void initState() {
    super.initState();
    _previewCatalog = widget.previewCatalog;
    _syncNameDrafts();
    _loadPolicies();
    if (_previewCatalog == null) {
      unawaited(_loadPreviewCatalog());
    }
  }

  Future<void> _loadPreviewCatalog() async {
    try {
      final catalog = await LpaSmdpCatalog.loadBundled();
      if (!mounted) return;
      setState(() => _previewCatalog = catalog);
    } catch (_) {
      // 资源未声明或读失败时不挡下载，只是没有国家/体积提示。
    }
  }

  @override
  void didUpdateWidget(EsimEditSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, _controller)) return;
    _feedbackVersion++;
    _feedback = '';
    _feedbackError = false;
    _feedbackUnknown = false;
    for (final name in _names.values) {
      name.dispose();
    }
    _names.clear();
    _policies.clear();
    _policyLoading.clear();
    _syncNameDrafts();
    _loadPolicies();
  }

  @override
  void dispose() {
    _lpa.dispose();
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  EsimSwitchTarget _policyKey(EsimProfile profile) => profile.target;

  void _syncNameDrafts() {
    final profiles =
        _controller.inventory.lastGoodData?.profiles ?? const <EsimProfile>[];
    for (final profile in profiles) {
      _names.putIfAbsent(
        _policyKey(profile),
        () => TextEditingController(text: profile.name),
      );
    }
  }

  Future<void> _loadPolicies() async {
    final controller = _controller;
    final version = ++_policyVersion;
    bool current() =>
        mounted &&
        identical(controller, _controller) &&
        !controller.isDisposed &&
        version == _policyVersion;
    final profiles =
        controller.inventory.lastGoodData?.profiles ?? const <EsimProfile>[];
    for (final profile in profiles) {
      _policyLoading.add(_policyKey(profile));
    }
    if (mounted) setState(() {});
    for (final profile in profiles) {
      final key = _policyKey(profile);
      try {
        final policy = await controller.peekPolicy(profile);
        if (!current()) return;
        if (policy != null) _policies[key] = policy;
      } catch (_) {
        if (!current()) return;
      } finally {
        if (current()) {
          _policyLoading.remove(key);
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _syncNameDrafts();
        final profiles =
            _controller.inventory.lastGoodData?.profiles ??
            const <EsimProfile>[];
        final hardware =
            _controller.hardware.lastGoodData ?? const <EuiccHardware>[];
        final current = profiles.where((profile) => profile.active).firstOrNull;
        final mutating = _mutating;
        return ListView(
          padding: OneInsets.scroll(context),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '编辑 eSIM',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: mutating
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const SystemIcon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: OneSpacing.item),
            SoftLabelGrid(
              children: <Widget>[
                SoftLabel(
                  title: '当前 Profile',
                  value: current?.name ?? '—',
                  sub: current?.provider,
                ),
                SoftLabel(
                  title: 'ICCID',
                  value: current?.iccidDisplay ?? '—',
                  mono: true,
                ),
                SoftLabel(
                  title: 'IMEI',
                  value: widget.imeiDisplay ?? '—',
                  mono: true,
                ),
              ],
            ),
            const SizedBox(height: OneSpacing.item),
            SegmentedButton<_EditTab>(
              segments: const <ButtonSegment<_EditTab>>[
                ButtonSegment<_EditTab>(
                  value: _EditTab.profiles,
                  label: Text('卡片管理'),
                  icon: SystemIcon(Icons.sim_card_outlined),
                ),
                ButtonSegment<_EditTab>(
                  value: _EditTab.download,
                  label: Text('下载 Profile'),
                  icon: SystemIcon(Icons.download_outlined),
                ),
              ],
              selected: <_EditTab>{_tab},
              onSelectionChanged: mutating
                  ? null
                  : (value) => setState(() => _tab = value.first),
            ),
            const SizedBox(height: OneSpacing.medium),
            if (_feedback.isNotEmpty)
              Text(
                _feedbackUnknown
                    ? '操作结果未知'
                    : _feedbackError
                    ? '操作失败'
                    : '已完成',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _feedbackError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            if (_feedback.isNotEmpty)
              Text(_feedback, style: Theme.of(context).textTheme.bodySmall),
            if (_tab == _EditTab.download)
              _downloadBody(mutating)
            else
              ..._profileGroups(profiles, hardware, mutating),
          ],
        );
      },
    );
  }

  List<Widget> _profileGroups(
    List<EsimProfile> profiles,
    List<EuiccHardware> hardware,
    bool mutating,
  ) {
    if (profiles.isEmpty) {
      return const <Widget>[Text('没有 eSIM'), Text('先读芯片，或到「下载 Profile」写入一张。')];
    }
    final grouped = <String, List<EsimProfile>>{};
    for (final profile in profiles) {
      final key = profile.eidDisplay.isEmpty ? '_' : profile.eidDisplay;
      grouped.putIfAbsent(key, () => <EsimProfile>[]).add(profile);
    }
    final widgets = <Widget>[];
    var index = 0;
    for (final entry in grouped.entries) {
      final chip = index < hardware.length ? hardware[index] : null;
      final title = chip?.slotLabel ?? 'eUICC';
      final sub = <String>[
        if (chip != null && chip.chipMaker.isNotEmpty) chip.chipMaker,
        if (entry.key != '_') 'EID · ${entry.key}',
        if (chip != null && chip.hasCapacity) '可用 ${chip.freeNvram}',
      ].join(' · ');
      widgets.add(
        OwSection(
          key: ValueKey<String>('esim-group:${entry.key}'),
          title: title,
          icon: Icons.memory_outlined,
          tone: PlateTone.purple,
          desc: sub.isEmpty ? null : sub,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < entry.value.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: OneSpacing.item),
                EsimProfileEditor(
                  key: ValueKey<EsimSwitchTarget>(entry.value[i].target),
                  profile: entry.value[i],
                  name: _names[_policyKey(entry.value[i])]!,
                  policy: _policies[_policyKey(entry.value[i])],
                  policyLoading: _policyLoading.contains(
                    _policyKey(entry.value[i]),
                  ),
                  mutating: mutating,
                  deviceOnline: widget.deviceOnline,
                  onRename: () => _rename(entry.value[i]),
                  onToggle: () => _toggle(entry.value[i]),
                  onDelete: () => _delete(entry.value[i]),
                  onSavePolicy: (policy) => _savePolicy(entry.value[i], policy),
                ),
              ],
            ],
          ),
        ),
      );
      widgets.add(const SizedBox(height: OneSpacing.medium));
      index += 1;
    }
    return widgets;
  }

  Widget _downloadBody(bool mutating) {
    final action = _controller.downloadAction;
    final progress = _controller.downloadProgress;
    final submitting = action.status == ActionStatus.submitting;
    return GlassTile(
      tone: PlateTone.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '下载 eSIM',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: OneSpacing.micro),
          Text(
            '粘贴 LPA 激活码。失败后不会自动重试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: OneSpacing.small),
          TextField(
            key: EsimPanelLpaKey.value,
            controller: _lpa,
            enabled: !submitting,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'LPA:1\$smdp\$matching',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_lpaPreviewCopy != null) ...<Widget>[
            const SizedBox(height: OneSpacing.item),
            _LpaSmdpPreviewTile(copy: _lpaPreviewCopy!),
          ],
          const SizedBox(height: OneSpacing.item),
          Wrap(
            spacing: OneSpacing.item,
            runSpacing: OneSpacing.item,
            alignment: WrapAlignment.end,
            children: <Widget>[
              if (submitting)
                OutlinedButton(
                  onPressed: _controller.cancelDownload,
                  child: const Text('取消'),
                ),
              FilledButton(
                onPressed: mutating || _lpa.text.trim().isEmpty
                    ? null
                    : _download,
                child: Text(submitting ? '下载中…' : '下载'),
              ),
            ],
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: OneSpacing.item),
            Builder(
              builder: (context) {
                final title = progress.isError
                    ? '下载失败'
                    : progress.isDone
                    ? '下载完成'
                    : '下载进度 ${progress.percent}%';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!(progress.isDone && title == _feedback))
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: progress.isError
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    if (progress.message.isNotEmpty &&
                        progress.message != title &&
                        progress.message != _feedback)
                      Text(
                        progress.message,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _rename(EsimProfile profile) async {
    if (_mutating || _controller.isDisposed) return;
    final name = _names[_policyKey(profile)]?.text.trim() ?? '';
    if (name.isEmpty) {
      setState(() {
        _feedback = '卡名字不能为空';
        _feedbackError = true;
        _feedbackUnknown = false;
      });
      return;
    }
    await _runEdit(
      (controller) => controller.renameProfile(profile, name),
      (controller) => controller.mutateAction,
      'eSIM 名称已更新',
    );
  }

  Future<void> _toggle(EsimProfile profile) async {
    await _runEdit(
      (controller) => profile.active
          ? controller.disableProfile(profile)
          : controller.switchProfile(profile),
      (controller) =>
          profile.active ? controller.mutateAction : controller.switchAction,
      profile.active ? 'eSIM 已禁用' : 'eSIM 已启用',
    );
  }

  Future<void> _delete(EsimProfile profile) async {
    if (_mutating || _controller.isDisposed) return;
    final controller = _controller;
    final version = _feedbackVersion;
    if (!profile.canDelete) {
      setState(() {
        _feedback = profile.deleteBlockedReason;
        _feedbackError = true;
        _feedbackUnknown = false;
      });
      return;
    }
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '删除 eSIM？',
      message:
          '删除「${profile.name}」（尾号 ${profile.iccidDisplay}）？芯片上的这张配置会清掉，本机无法恢复。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !_isCurrentEdit(controller, version)) return;
    await _runEdit(
      (controller) => controller.deleteProfile(profile),
      (controller) => controller.mutateAction,
      '已删除「${profile.name}」',
    );
  }

  Future<void> _savePolicy(EsimProfile profile, CardPolicy policy) async {
    await _runEdit(
      (controller) => controller.savePolicy(
        target: profile.target,
        apn: policy.apn,
        ipVersion: policy.ipVersion,
        networkEnabled: policy.networkEnabled,
        vowifiEnabled: policy.vowifiEnabled,
        airplaneEnabled: policy.airplaneEnabled,
        mbnProfile: policy.mbnProfile,
        voicePath: policy.voicePath,
      ),
      (controller) => controller.policyAction,
      profile.active
          ? (widget.deviceOnline ? '当前在线卡：改动立即生效' : '设备离线：改动已保存，上线后生效')
          : '未激活卡：改动将在此卡激活后生效',
      onSuccess: () => _policies[_policyKey(profile)] = policy,
    );
  }

  Future<void> _download() async {
    if (_mutating || _controller.isDisposed) return;
    final controller = _controller;
    final version = ++_feedbackVersion;
    setState(() => _feedback = '');
    await controller.download(_lpa.text);
    if (!_isCurrentEdit(controller, version)) return;
    final status = controller.downloadAction.status;
    // 已被「取消」置回 idle、或已被新一次下载接管（submitting）时，这次返回不算结果。
    if (status != ActionStatus.succeeded && status != ActionStatus.failed) {
      return;
    }
    setState(() {
      _feedbackError = status == ActionStatus.failed;
      _feedbackUnknown = controller.downloadAction.isUnknownOutcome;
      _feedback = _feedbackUnknown
          ? '超时或断线，结果未知。请核对卡片状态，不会自动重试。'
          : _feedbackError
          ? '下载失败'
          : '下载完成';
    });
  }

  bool _isCurrentEdit(EsimController controller, int version) =>
      mounted &&
      !controller.isDisposed &&
      identical(controller, _controller) &&
      version == _feedbackVersion;

  Future<void> _runEdit(
    Future<bool> Function(EsimController) operation,
    ActionState Function(EsimController) action,
    String ok, {
    VoidCallback? onSuccess,
  }) async {
    if (_mutating || _controller.isDisposed) return;
    final controller = _controller;
    final version = ++_feedbackVersion;
    setState(() => _feedback = '');
    final saved = await operation(controller);
    if (!_isCurrentEdit(controller, version)) return;
    final outcome = action(controller);
    if (!saved && outcome.status != ActionStatus.failed) return;
    setState(() {
      _feedbackError = !saved;
      _feedbackUnknown = !saved && outcome.isUnknownOutcome;
      if (saved) onSuccess?.call();
      _feedback = saved
          ? ok
          : _feedbackUnknown
          ? '超时或断线，结果未知。请核对卡片状态，不会自动重试。'
          : '网关没有确认这项改动。';
    });
  }

  SmdpPreviewCopy? get _lpaPreviewCopy {
    final catalog = _previewCatalog;
    if (catalog == null) return null;
    final chips = _controller.hardware.lastGoodData ?? const <EuiccHardware>[];
    final chip = chips.isEmpty ? null : chips.first;
    return formatSmdpPreview(
      previewLpaActivation(
        _lpa.text,
        eid: chip?.eidPrefix ?? '',
        freeNvramBytes: chip?.freeNvramBytes,
        catalog: catalog,
      ),
    );
  }
}

final class _LpaSmdpPreviewTile extends StatelessWidget {
  const _LpaSmdpPreviewTile({required this.copy});

  final SmdpPreviewCopy copy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyedSubtree(
      key: EsimPanelLpaPreviewKey.value,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  copy.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (copy.size.isNotEmpty)
                Text(copy.size, style: theme.textTheme.bodySmall),
            ],
          ),
          if (copy.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.micro),
            Text(copy.detail, style: theme.textTheme.bodySmall),
          ],
          if (copy.warning.isNotEmpty) ...<Widget>[
            const SizedBox(height: OneSpacing.micro),
            Text(
              copy.warning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 与切卡框共用同一个 LPA 输入 key，单测仍能 `EsimPanel.lpaFieldKey` 找到。
abstract final class EsimPanelLpaKey {
  static const Key value = Key('esim-lpa-field');
}

abstract final class EsimPanelLpaPreviewKey {
  static const Key value = Key('esim-lpa-preview');
}
