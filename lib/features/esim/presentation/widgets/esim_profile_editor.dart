import 'package:flutter/material.dart';

import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/console_layout.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../domain/card_policy.dart';
import '../../domain/esim.dart';
import 'mbn_profile_field.dart';

final class EsimProfileEditor extends StatefulWidget {
  const EsimProfileEditor({
    required this.profile,
    required this.name,
    required this.policy,
    required this.policyLoading,
    required this.mutating,
    required this.deviceOnline,
    required this.onRename,
    required this.onToggle,
    required this.onDelete,
    required this.onSavePolicy,
    super.key,
  });

  final EsimProfile profile;
  final TextEditingController name;
  final CardPolicy? policy;
  final bool policyLoading;
  final bool mutating;
  final bool deviceOnline;
  final VoidCallback onRename;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<CardPolicy> onSavePolicy;

  @override
  State<EsimProfileEditor> createState() => _EsimProfileEditorState();
}

final class _EsimProfileEditorState extends State<EsimProfileEditor> {
  late CardIpVersion _ip;
  late bool _network;
  late bool _vowifi;
  late bool _airplane;
  late String _mbn;
  late CardVoicePath _voice;
  final TextEditingController _apn = TextEditingController();
  bool _seeded = false;

  @override
  void didUpdateWidget(EsimProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.policy, widget.policy)) _seeded = false;
    _seed();
  }

  @override
  void initState() {
    super.initState();
    _ip = CardIpVersion.ipv4v6;
    _network = true;
    _vowifi = true;
    _airplane = true;
    _mbn = '';
    _voice = CardVoicePath.vowifi;
    _seed();
  }

  @override
  void dispose() {
    _apn.dispose();
    super.dispose();
  }

  void _seed() {
    final policy = widget.policy;
    if (policy == null || _seeded) return;
    _apn.text = policy.apn;
    _ip = policy.ipVersion;
    _network = policy.networkEnabled;
    _vowifi = policy.vowifiEnabled;
    _airplane = policy.airplaneEnabled;
    _mbn = policy.mbnProfile;
    _voice = policy.voicePath;
    _seeded = true;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final theme = Theme.of(context);
    return GlassTile(
      tone: profile.active ? PlateTone.green : null,
      selected: profile.active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  profile.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (profile.active)
                const Nameplate(label: '当前', ready: true, tone: PlateTone.green)
              else if (profile.locked)
                const Nameplate(label: '物理卡', tone: PlateTone.neutral)
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
          const SizedBox(height: OneSpacing.micro),
          Text(
            'ICCID · ${profile.iccidDisplay}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: OneSpacing.item),
          TextField(
            controller: widget.name,
            enabled: !widget.mutating && !profile.locked,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: OneSpacing.item),
          Wrap(
            spacing: OneSpacing.small,
            runSpacing: OneSpacing.small,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: widget.mutating || profile.locked
                    ? null
                    : widget.onRename,
                child: const Text('改名'),
              ),
              OutlinedButton(
                onPressed: widget.mutating || profile.locked
                    ? null
                    : widget.onToggle,
                child: Text(profile.active ? '禁用' : '启用'),
              ),
              OutlinedButton(
                onPressed: widget.mutating || !profile.canDelete
                    ? null
                    : widget.onDelete,
                child: Text(
                  profile.canDelete ? '删除' : profile.deleteBlockedReason,
                ),
              ),
            ],
          ),
          const SizedBox(height: OneSpacing.item),
          if (widget.policyLoading)
            const OneStatusProgress(
              label: '正在读取卡策略',
              kind: OneProgressKind.linear,
            )
          else if (widget.policy == null)
            const Text('卡策略暂不可用')
          else ...<Widget>[
            Text(
              profile.active
                  ? (widget.deviceOnline ? '当前在线卡：改动立即生效' : '设备离线：改动已保存，上线后生效')
                  : '未激活卡：改动将在此卡激活后生效',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开启网络'),
              value: _network,
              onChanged: widget.mutating
                  ? null
                  : (value) => setState(() => _network = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VoWiFi'),
              value: _vowifi,
              onChanged: widget.mutating
                  ? null
                  : (value) => setState(() => _vowifi = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('飞行模式'),
              value: _airplane,
              onChanged: widget.mutating
                  ? null
                  : (value) => setState(() => _airplane = value),
            ),
            DropdownButtonFormField<CardIpVersion>(
              key: ValueKey<CardIpVersion>(_ip),
              initialValue: _ip,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'IP 版本',
                isDense: true,
              ),
              items: <DropdownMenuItem<CardIpVersion>>[
                for (final version in CardIpVersion.values)
                  DropdownMenuItem<CardIpVersion>(
                    value: version,
                    child: Text(
                      version.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: widget.mutating
                  ? null
                  : (value) {
                      if (value != null) setState(() => _ip = value);
                    },
            ),
            const SizedBox(height: OneSpacing.item),
            TextField(
              controller: _apn,
              enabled: !widget.mutating,
              decoration: const InputDecoration(
                labelText: 'APN（可选）',
                isDense: true,
              ),
            ),
            const SizedBox(height: OneSpacing.item),
            DropdownButtonFormField<CardVoicePath>(
              key: ValueKey<CardVoicePath>(_voice),
              initialValue: _voice,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '语音',
                isDense: true,
              ),
              items: <DropdownMenuItem<CardVoicePath>>[
                for (final path in CardVoicePath.values)
                  DropdownMenuItem<CardVoicePath>(
                    value: path,
                    child: Text(path.label),
                  ),
              ],
              onChanged: widget.mutating
                  ? null
                  : (value) {
                      if (value != null) setState(() => _voice = value);
                    },
            ),
            Padding(
              padding: const EdgeInsets.only(top: OneSpacing.micro),
              child: Text(
                kVoicePathHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.75,
                  ),
                ),
              ),
            ),
            const SizedBox(height: OneSpacing.item),
            MbnProfileField(
              value: _mbn,
              enabled: !widget.mutating,
              dense: true,
              onChanged: (value) => setState(() => _mbn = value),
            ),
            const SizedBox(height: OneSpacing.item),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: widget.mutating
                    ? null
                    : () => widget.onSavePolicy(
                        CardPolicy(
                          apn: _apn.text.trim(),
                          ipVersion: _ip,
                          networkEnabled: _network,
                          vowifiEnabled: _vowifi,
                          airplaneEnabled: _airplane,
                          mbnProfile: _mbn,
                          voicePath: _voice,
                        ),
                      ),
                child: const Text('保存卡策略'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
