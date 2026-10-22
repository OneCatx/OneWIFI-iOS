import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../devices/domain/device.dart';
import '../../devices/state/device_list_controller.dart';
import '../state/calls_controller.dart';
import 'call_dialpad.dart';
import 'call_glass.dart';
import 'call_history.dart';
import 'call_settings.dart';
import 'native_call_panel.dart';

final class CallsScreen extends StatefulWidget {
  const CallsScreen({required this.calls, required this.devices, super.key});
  static const Key rootKey = Key('calls-screen');
  final CallsController calls;
  final DeviceListController devices;
  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

final class _CallsScreenState extends State<CallsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _dialField;
  bool _history = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dialField = TextEditingController(text: widget.calls.dialNumber);
    widget.calls.addListener(_onChanged);
    widget.devices.addListener(_onDevices);
    widget.calls.setPollUiActive(true);
    _onDevices();
    _loadDevicesIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same T3 variable as tab mount/unmount: pause HTTP poll off-foreground.
    widget.calls.setPollUiActive(state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant CallsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.calls, widget.calls)) {
      oldWidget.calls.setPollUiActive(false);
      oldWidget.calls.removeListener(_onChanged);
      widget.calls.addListener(_onChanged);
      widget.calls.setPollUiActive(true);
      _onChanged();
    }
    if (!identical(oldWidget.devices, widget.devices)) {
      oldWidget.devices.removeListener(_onDevices);
      widget.devices.addListener(_onDevices);
    }
    if (!identical(oldWidget.calls, widget.calls) ||
        !identical(oldWidget.devices, widget.devices)) {
      _onDevices();
      _loadDevicesIfNeeded();
    }
  }

  void _loadDevicesIfNeeded() {
    if (!widget.calls.usesNative &&
        widget.devices.state.status == QueryStatus.initial) {
      unawaited(widget.devices.load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.calls.setPollUiActive(false);
    widget.calls.removeListener(_onChanged);
    widget.devices.removeListener(_onDevices);
    _dialField.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_dialField.text != widget.calls.dialNumber) {
      _dialField.value = TextEditingValue(
        text: widget.calls.dialNumber,
        selection: TextSelection.collapsed(
          offset: widget.calls.dialNumber.length,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  void _onDevices() {
    if (widget.calls.usesNative) return;
    widget.calls.syncDevices(
      widget.devices.state.lastGoodData?.devices ?? const <DeviceSnapshot>[],
    );
    if (mounted) setState(() {});
  }

  List<({String id, String label})> get _devices => widget.calls.usesNative
      ? [
          for (final d in widget.calls.nativeSnapshot?.devices ?? [])
            (id: d.id, label: d.label),
        ]
      : [
          for (final d
              in widget.devices.state.lastGoodData?.devices ??
                  <DeviceSnapshot>[])
            (id: d.id, label: d.name),
        ];

  Future<void> _chooseDevice() => showOneGlassPopup<void>(
        context: context,
        builder: (context) => ListenableBuilder(
          listenable: Listenable.merge([widget.calls, widget.devices]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('选择通话设备', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (_devices.isEmpty) const Text('等待网关设备状态'),
              for (final device in _devices)
                ListTile(
                  leading: const Icon(Icons.sim_card_outlined),
                  title: Text(device.label),
                  trailing: widget.calls.deviceId == device.id
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () {
                    widget.calls.selectDevice(device.id);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      );

  List<Widget> _chrome(ThemeData theme) {
    final calls = widget.calls;
    final selected = _devices.where((d) => d.id == calls.deviceId).firstOrNull;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '电话',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (calls.usesNative) NativeCallSettingsButton(calls: calls),
        ],
      ),
      const SizedBox(height: 16),
      CallGlass(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('拨号'),
              icon: Icon(Icons.dialpad_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text('最近通话'),
              icon: Icon(Icons.history_rounded),
            ),
          ],
          selected: {_history},
          onSelectionChanged: (value) => setState(() => _history = value.single),
          showSelectedIcon: false,
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton.icon(
          key: const Key('calls-device-picker'),
          onPressed: _devices.isEmpty ? null : _chooseDevice,
          icon: const Icon(Icons.sim_card_outlined, size: 18),
          label: Text(
            selected?.label ??
                (calls.usesNative && calls.nativeSnapshot?.isFresh != true
                    ? '等待网关设备状态'
                    : '暂无通话设备'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (calls.notice.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CallGlass(
            padding: const EdgeInsets.all(14),
            child: Text(
              calls.notice,
              style: TextStyle(
                color: calls.noticeError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      if (calls.usesNative) NativeCallPanel(calls: calls),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    final theme = Theme.of(context);
    final chrome = _chrome(theme);

    if (!_history) {
      return ListView(
        key: CallsScreen.rootKey,
        padding: OneInsets.scroll(context),
        children: [
          ...chrome,
          CallDialpad(calls: calls, field: _dialField),
        ],
      );
    }

    final rows = CallHistory.rowsFor(calls);
    return ListView.builder(
      key: CallsScreen.rootKey,
      padding: OneInsets.scroll(context),
      itemCount: chrome.length + 1 + rows.length,
      itemBuilder: (context, index) {
        if (index < chrome.length) {
          return chrome[index];
        }
        if (index == chrome.length) {
          return CallHistory.header(
            context: context,
            calls: calls,
            empty: rows.isEmpty,
          );
        }
        return CallHistory.tile(
          context: context,
          calls: calls,
          call: rows[index - chrome.length - 1],
          onRedial: (call) {
            calls.selectDevice(call.deviceId);
            calls.setDialNumber(call.number);
            setState(() => _history = false);
          },
        );
      },
    );
  }
}
