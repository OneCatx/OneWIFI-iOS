import 'package:flutter/material.dart';

import '../../../design/tokens/one_tokens.dart';
import '../domain/device.dart';

final class DeviceRegisterDialog extends StatefulWidget {
  const DeviceRegisterDialog({
    required this.device,
    super.key,
  });

  final DiscoveredDevice device;

  @override
  State<DeviceRegisterDialog> createState() => _DeviceRegisterDialogState();
}

final class _DeviceRegisterDialogState extends State<DeviceRegisterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _deviceIdController;
  late final TextEditingController _nameController;
  late final TextEditingController _simPinController;
  bool _showSimPin = false;

  @override
  void initState() {
    super.initState();
    _deviceIdController = TextEditingController(text: _generateDeviceId());
    _nameController = TextEditingController(
      text: widget.device.readerName.isNotEmpty
          ? widget.device.readerName
          : '设备 ${widget.device.imei.substring(widget.device.imei.length - 4)}',
    );
    _simPinController = TextEditingController();
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _nameController.dispose();
    _simPinController.dispose();
    super.dispose();
  }

  String _generateDeviceId() {
    final imei = widget.device.imei;
    final suffix = imei.isNotEmpty && imei.length >= 6
        ? imei.substring(imei.length - 6)
        : DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return 'dev-$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: const Text('注册设备'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.device.readerName.isNotEmpty
                      ? widget.device.readerName
                      : 'IMEI ${widget.device.imei}',
                  style: theme.textTheme.titleMedium,
                ),
                subtitle: Text(
                  '类型: ${widget.device.deviceType}\n'
                  '路径: ${widget.device.controlPath}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: OneSpacing.medium),
              TextFormField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: '设备 ID *',
                  helperText: '唯一标识此设备的 ID',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入设备 ID';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
                    return 'ID 只能包含字母、数字、下划线和连字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: OneSpacing.medium),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '设备名称',
                  helperText: '用于显示的友好名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: OneSpacing.medium),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _showSimPin,
                onChanged: (value) {
                  setState(() {
                    _showSimPin = value ?? false;
                  });
                },
                title: const Text('设置 SIM PIN'),
              ),
              if (_showSimPin) ...<Widget>[
                const SizedBox(height: OneSpacing.small),
                TextFormField(
                  controller: _simPinController,
                  decoration: const InputDecoration(
                    labelText: 'SIM PIN',
                    helperText: '4-8 位数字',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  validator: (value) {
                    if (!_showSimPin) return null;
                    if (value == null || value.isEmpty) return null;
                    if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
                      return 'PIN 必须是 4-8 位数字';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(<String, String>{
                'deviceId': _deviceIdController.text.trim(),
                'name': _nameController.text.trim(),
                'simPin': _showSimPin ? _simPinController.text.trim() : '',
                'discoveryKey': widget.device.discoveryKey,
                'deviceType': widget.device.deviceType,
              });
            }
          },
          child: const Text('注册'),
        ),
      ],
    );
  }
}
