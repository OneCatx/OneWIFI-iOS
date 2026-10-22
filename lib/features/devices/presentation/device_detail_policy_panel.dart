part of 'device_detail_view.dart';

/// WEB `OneWifiOverviewPolicyCard`：一个「卡策略」框装下 ICCID 条、IP 版本、APN
/// 与三个开关。开关立刻下发到模组；APN / IP 版本按当前卡 ICCID 显式保存。
final class _CardPolicyPanel extends StatefulWidget {
  const _CardPolicyPanel({
    required this.device,
    required this.esim,
    required this.submitting,
    required this.onNetwork,
    required this.onVowifi,
    required this.onFlight,
  });

  final DeviceSnapshot device;
  final EsimController? esim;
  final bool submitting;
  final ValueChanged<bool> onNetwork;
  final ValueChanged<bool> onVowifi;
  final ValueChanged<bool> onFlight;

  @override
  State<_CardPolicyPanel> createState() => _CardPolicyPanelState();
}

final class _CardPolicyPanelState extends State<_CardPolicyPanel> {
  final TextEditingController _apn = TextEditingController();
  CardIpVersion _ipVersion = CardIpVersion.ipv4v6;
  String _mbn = '';
  String _seededMbn = '';
  CardVoicePath _voicePath = CardVoicePath.vowifi;
  CardVoicePath _seededVoicePath = CardVoicePath.vowifi;
  bool _seeded = false;
  EsimSwitchTarget? _draftTarget;

  @override
  void didUpdateWidget(_CardPolicyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.esim, widget.esim)) {
      _draftTarget = null;
      _seeded = false;
      _apn.clear();
      _ipVersion = CardIpVersion.ipv4v6;
    }
  }

  @override
  void dispose() {
    _apn.dispose();
    super.dispose();
  }

  void _seed(EsimSwitchTarget? target, CardPolicy? policy) {
    if (_draftTarget != target) {
      _draftTarget = target;
      _seeded = false;
      _apn.clear();
      _ipVersion = CardIpVersion.ipv4v6;
      _mbn = '';
      _seededMbn = '';
      _voicePath = CardVoicePath.vowifi;
      _seededVoicePath = CardVoicePath.vowifi;
    }
    if (policy == null || _seeded) return;
    _apn.text = policy.apn;
    _ipVersion = policy.ipVersion;
    _mbn = policy.mbnProfile;
    _seededMbn = policy.mbnProfile;
    _voicePath = policy.voicePath;
    _seededVoicePath = policy.voicePath;
    _seeded = true;
  }

  @override
  Widget build(BuildContext context) {
    final esim = widget.esim;
    if (esim == null) return _build(context, null);
    return AnimatedBuilder(
      animation: esim,
      builder: (context, _) => _build(context, esim),
    );
  }

  Widget _build(BuildContext context, EsimController? esim) {
    final device = widget.device;
    final theme = Theme.of(context);
    final policy = esim?.policy.lastGoodData;
    final policyAction = esim?.policyActionTarget == esim?.policyTarget
        ? esim?.policyAction
        : null;
    final savingPolicy = esim?.policyAction.status == ActionStatus.submitting;
    final hasCard = esim?.policyTarget != null;
    _seed(esim?.policyTarget, policy);
    final editable = hasCard && _seeded && !savingPolicy;
    final locked = widget.submitting;
    final networkLocked = device.vowifiEnabled || device.flightMode;
    final flightLocked = device.vowifiEnabled;
    final iccid = device.identities.iccidDisplay;
    return OwSection(
      title: '卡策略',
      icon: Icons.tune,
      tone: PlateTone.blue,
      desc: widget.submitting || savingPolicy ? '保存中…' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassTile(
            child: Row(
              children: <Widget>[
                Text(
                  '当前卡 ICCID',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: OneSpacing.item),
                Expanded(
                  child: Text(
                    iccid ?? '尚未识别',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (esim != null) ...<Widget>[
            const SizedBox(height: OneSpacing.item),
            _TilePair(
              left: _PolicyFieldTile(
                label: 'IP 版本',
                hint: hasCard ? '下次开启网络时生效' : '先读芯片或切到一张卡',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CardIpVersion>(
                    value: _ipVersion,
                    isDense: true,
                    isExpanded: true,
                    onChanged: !editable
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _ipVersion = value);
                            }
                          },
                    items: <DropdownMenuItem<CardIpVersion>>[
                      for (final version in CardIpVersion.values)
                        DropdownMenuItem<CardIpVersion>(
                          value: version,
                          child: Text(version.label),
                        ),
                    ],
                  ),
                ),
              ),
              right: _PolicyFieldTile(
                label: 'APN（可选）',
                hint: hasCard ? '下次开启网络时生效' : '先读芯片或切到一张卡',
                child: TextField(
                  key: DeviceDetailView.apnFieldKey,
                  controller: _apn,
                  enabled: editable,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '留空自动识别',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: OneSpacing.small,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: OneSpacing.item),
            GlassTile(
              child: _VoicePathField(
                value: _voicePath,
                enabled: editable,
                onChanged: (value) => setState(() => _voicePath = value),
              ),
            ),
            const SizedBox(height: OneSpacing.item),
            GlassTile(
              child: MbnProfileField(
                value: _mbn,
                enabled: editable,
                dense: true,
                onChanged: (value) => setState(() => _mbn = value),
              ),
            ),
          ],
          const SizedBox(height: OneSpacing.item),
          _TilePair(
            left: _PolicyToggleTile(
              label: '开启网络',
              value: device.networkEnabled,
              enabled: !locked && !networkLocked,
              hint: 'VoWiFi/飞行开启时不可用',
              onChanged: widget.onNetwork,
            ),
            right: _PolicyToggleTile(
              label: 'VoWiFi',
              value: device.vowifiEnabled,
              enabled: !locked,
              hint: '启用后进飞行模式',
              onChanged: widget.onVowifi,
            ),
          ),
          const SizedBox(height: OneSpacing.item),
          _PolicyToggleTile(
            label: '飞行模式',
            value: device.flightMode,
            enabled: !locked && !flightLocked,
            hint: 'VoWiFi 开启时由其接管',
            onChanged: widget.onFlight,
          ),
          if (esim != null && hasCard) ...<Widget>[
            const SizedBox(height: OneSpacing.item),
            GlassActionRow(
              children: <Widget>[
                GlassActionButton(
                  icon: Icons.save_outlined,
                  label: savingPolicy ? '保存中…' : '保存 APN / IP',
                  busy: savingPolicy,
                  onPressed: editable ? () => _confirmSave(esim) : null,
                ),
              ],
            ),
          ],
          if (policyAction?.status == ActionStatus.succeeded)
            Padding(
              padding: const EdgeInsets.only(top: OneSpacing.item),
              child: Text(
                '策略已保存',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          if (policyAction != null &&
              policyAction.status == ActionStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: OneSpacing.item),
              child: Text(
                policyAction.isUnknownOutcome ? '保存结果未知' : '策略未保存',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmSave(EsimController esim) async {
    final target = _draftTarget;
    if (target == null || !_seeded) return;
    final apn = _apn.text.trim();
    final ipVersion = _ipVersion;
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '保存卡策略?',
      message: '写入 APN、IP 版本和改过的语音路径。改过的 MBN 才会下发。不会自动重试。',
      confirmLabel: '保存',
    );
    if (confirmed == true &&
        mounted &&
        identical(esim, widget.esim) &&
        target == esim.policyTarget) {
      await esim.savePolicy(
        target: target,
        apn: apn,
        ipVersion: ipVersion,
        mbnProfile: _mbn == _seededMbn ? null : _mbn,
        voicePath: _voicePath == _seededVoicePath ? null : _voicePath,
      );
    }
  }
}

/// 两块瓷片并排（WEB `policy-grid` 两列）；窄屏退成上下排。
final class _VoicePathField extends StatelessWidget {
  const _VoicePathField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final CardVoicePath value;
  final bool enabled;
  final ValueChanged<CardVoicePath> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<CardVoicePath>(
          key: ValueKey<String>('card-voice-path:${value.apiValue}'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '语音', isDense: true),
          items: <DropdownMenuItem<CardVoicePath>>[
            for (final path in CardVoicePath.values)
              DropdownMenuItem<CardVoicePath>(
                value: path,
                child: Text(path.label),
              ),
          ],
          onChanged: enabled
              ? (next) {
                  if (next != null) onChanged(next);
                }
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          kVoicePathHint,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// 两块瓷片并排（WEB `policy-grid` 两列）；窄屏退成上下排。
final class _TilePair extends StatelessWidget {
  const _TilePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 300) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            left,
            const SizedBox(height: OneSpacing.item),
            right,
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: OneSpacing.item),
            Expanded(child: right),
          ],
        ),
      );
    },
  );
}

/// WEB `policy-field`：标签在上、控件居中、灰字提示在下。
final class _PolicyFieldTile extends StatelessWidget {
  const _PolicyFieldTile({
    required this.label,
    required this.child,
    required this.hint,
  });

  final String label;
  final Widget child;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GroupLabel(text: label),
          const SizedBox(height: OneSpacing.micro),
          child,
          const SizedBox(height: OneSpacing.micro),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// WEB `policy-field` + `policy-toggle`：开着→绿色瓷片；关着→黑白玻璃。
final class _PolicyToggleTile extends StatelessWidget {
  const _PolicyToggleTile({
    required this.label,
    required this.value,
    required this.enabled,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final String hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassTile(
      tone: value ? PlateTone.green : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
