part of 'device_detail_view.dart';

/// WEB `carrier-banner` 里的 `sim-visual`：芯片 logo 和归属运营商居中。
/// 驻网（小区 / 频段 / 信号）不画在这里，避免和运行状态框抢同一套字。
final class _SimVisual extends StatelessWidget {
  const _SimVisual({required this.operatorName});

  final String operatorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = OneTheme.isDark(theme);
    final title = operatorName.isEmpty ? '—' : operatorName;
    return ClipRRect(
      borderRadius: BorderRadius.circular(OneRadii.control),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              OwAccent.teal.withValues(alpha: dark ? 0.22 : 0.16),
              OwAccent.blue.withValues(alpha: dark ? 0.14 : 0.10),
              Colors.transparent,
            ],
          ),
          border: Border.all(
            color: OwAccent.teal.withValues(alpha: dark ? 0.26 : 0.30),
            width: OneSpacing.hairline,
          ),
          borderRadius: BorderRadius.circular(OneRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(OneSpacing.item + OneSpacing.micro),
          child: Column(
            children: <Widget>[
              Container(
                width: 48,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      OwAccent.teal.withValues(alpha: 0.85),
                      OwAccent.blue.withValues(alpha: 0.55),
                    ],
                  ),
                  boxShadow: OwAccent.plateShadow(OwAccent.teal),
                ),
                child: CustomPaint(painter: _SimContactsPainter(dark: dark)),
              ),
              const SizedBox(height: OneSpacing.small),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SIM 金属触点的几根刻线。
final class _SimContactsPainter extends CustomPainter {
  const _SimContactsPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.28)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final inset = size.width * 0.18;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset * 0.8,
        size.width - inset * 2,
        size.height - inset * 1.6,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, paint);
    final midY = size.height / 2;
    canvas.drawLine(Offset(rect.left, midY), Offset(rect.right, midY), paint);
    final thirdX = rect.left + rect.width / 3;
    canvas.drawLine(
      Offset(thirdX, rect.top),
      Offset(thirdX, rect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(thirdX * 2 - rect.left, rect.top),
      Offset(thirdX * 2 - rect.left, rect.bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SimContactsPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

/// WEB `runtime-progress--switch`：五段 停网 → 飞行 → 写卡 → 校验 → 恢复。
/// 嵌在切卡框最上方的玻璃容器里，不再单独占一个框。
final class _SwitchProgressPanel extends StatelessWidget {
  const _SwitchProgressPanel({required this.progress, required this.switching});

  static const List<String> _labels = <String>['停网', '飞行', '写卡', '校验', '恢复'];

  final DeviceEsimSwitch progress;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final failed = progress.stages.contains(DeviceSwitchStageState.failed);
    final done =
        !progress.active &&
        !failed &&
        progress.stages.every((s) => s == DeviceSwitchStageState.ready);
    return GlassTile(
      semanticLabel: '切卡进度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _GroupLabel(text: '切卡进度')),
              if (switching)
                const Nameplate(label: '进行中', tone: PlateTone.blue)
              else if (failed)
                const Nameplate(label: '失败', tone: PlateTone.red)
              else if (done)
                const Nameplate(
                  label: '已完成',
                  ready: true,
                  tone: PlateTone.green,
                ),
            ],
          ),
          const SizedBox(height: OneSpacing.small),
          StageRow(
            semanticLabel: '切卡进度',
            stages: <(String, StageState)>[
              for (var i = 0; i < _labels.length; i++)
                (
                  _labels[i],
                  i < progress.stages.length
                      ? _stageState(progress.stages[i])
                      : StageState.pending,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static StageState _stageState(DeviceSwitchStageState state) =>
      switch (state) {
        DeviceSwitchStageState.pending => StageState.pending,
        DeviceSwitchStageState.running => StageState.active,
        DeviceSwitchStageState.ready => StageState.ready,
        DeviceSwitchStageState.failed => StageState.failed,
      };
}

/// WEB SIM / 设备框：框头眼睛揭开身份号码；[重启模组] 仍在右侧。
/// 「当前进度」已挪到运行状态框。
final class _SimPanel extends StatefulWidget {
  const _SimPanel({
    required this.detail,
    required this.esim,
    required this.onReboot,
  });

  final DeviceDetail detail;
  final EsimController? esim;
  final VoidCallback onReboot;

  @override
  State<_SimPanel> createState() => _SimPanelState();
}

final class _SimPanelState extends State<_SimPanel> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.esim;
    if (controller == null) return _build(context, null, const []);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _build(
        context,
        controller.inventory.lastGoodData?.profiles
            .where((profile) => profile.active)
            .firstOrNull,
        controller.hardware.lastGoodData ?? const <EuiccHardware>[],
      ),
    );
  }

  Widget _build(
    BuildContext context,
    EsimProfile? activeProfile,
    List<EuiccHardware> hardware,
  ) {
    final device = widget.detail.device;
    final identities = device.identities;
    return OwSection(
      semanticLabel: '设备详情',
      title: 'SIM / 设备',
      icon: Icons.sim_card_outlined,
      tone: PlateTone.purple,
      actions: GlassActionRow(
        children: <Widget>[
          IconButton(
            key: const Key('device-identities-reveal'),
            tooltip: _revealed ? '隐藏身份号码' : '显示身份号码',
            visualDensity: VisualDensity.compact,
            icon: SystemIcon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
          if (device.type != DeviceType.wifi410)
            GlassActionButton(
              icon: Icons.power_settings_new,
              label: '重启模组',
              onPressed: widget.onReboot,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SimVisual(operatorName: device.modem.operatorName),
          const SizedBox(height: OneSpacing.medium),
          SoftLabelGrid(
            children: <Widget>[
              SoftLabel(
                title: 'IMEI',
                value: _identityLine(
                  identities.imeiReveal,
                  identities.imeiDisplay,
                ),
                mono: true,
              ),
              SoftLabel(
                title: 'ICCID',
                value: _identityLine(
                  identities.iccidReveal,
                  identities.iccidDisplay,
                ),
                mono: true,
              ),
              SoftLabel(
                title: 'IMSI',
                value: _identityLine(
                  identities.imsiReveal,
                  identities.imsiDisplay,
                ),
                mono: true,
              ),
              SoftLabel(
                title: '本机号码',
                value: _identityLine(
                  identities.phoneReveal,
                  identities.phoneDisplay,
                ),
                mono: true,
              ),
              SoftLabel(
                title: activeProfile?.provider == '国内卡' ? '当前卡' : '当前 eSIM',
                value: activeProfile?.name ?? '—',
                sub: activeProfile == null || activeProfile.provider.isEmpty
                    ? null
                    : activeProfile.provider,
              ),
              SoftLabel(
                title: '原运营商',
                value: _value(device.modem.operatorName),
              ),
              SoftLabel(
                title: '固件版本',
                value: _value(device.modem.firmware ?? ''),
                mono: true,
              ),
              SoftLabel(title: '模组', value: _value(device.modem.model)),
              for (final chip in hardware) ...<Widget>[
                SoftLabel(
                  title: '${chip.slotLabel} 厂商',
                  value: chip.chipMaker.isEmpty ? '未知硅片' : chip.chipMaker,
                  sub: chip.nameplate == unknownEuiccNameplate
                      ? null
                      : chip.nameplate,
                ),
                SoftLabel(
                  title: '${chip.slotLabel} 可用容量',
                  value: chip.hasCapacity ? chip.freeNvram : '—',
                  mono: true,
                ),
              ],
              SoftLabel(title: '流量', value: _traffic(widget.detail.traffic)),
            ],
          ),
        ],
      ),
    );
  }

  String _identityLine(String? reveal, String? display) {
    if (_revealed) {
      final full = reveal?.trim() ?? '';
      if (full.isNotEmpty) return full;
    }
    return display ?? '—';
  }
}
