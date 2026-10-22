import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// iOS 用 SF Symbol。其它平台保持原来的 Material 图标。
final class SystemIcon extends StatelessWidget {
  const SystemIcon(this.icon, {this.size, this.color, super.key});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = IconTheme.of(context);
    final side = size ?? resolved.size ?? 24;
    final ink = color ?? resolved.color;
    return Icon(icon, size: side, color: ink);
  }
}

/// iOS 用 UISwitch。其它平台保持 Material 开关。
final class SystemSwitch extends StatefulWidget {
  const SystemSwitch({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<SystemSwitch> createState() => _SystemSwitchState();
}

final class _SystemSwitchState extends State<SystemSwitch> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(SystemSwitch old) {
    super.didUpdateWidget(old);
    _channel?.invokeMethod('update', {
      'value': widget.value,
      'enabled': widget.onChanged != null,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ios) {
      return Switch(value: widget.value, onChanged: widget.onChanged);
    }
    return SizedBox(
      width: 51,
      height: 31,
      child: UiKitView(
        viewType: 'onewifi/system_switch',
        creationParams: {
          'value': widget.value,
          'enabled': widget.onChanged != null,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          _channel = MethodChannel('com.oneims.onewifi/system_switch/$id')
            ..setMethodCallHandler((call) async {
              if (call.method == 'changed') widget.onChanged?.call(call.arguments == true);
            });
        },
      ),
    );
  }
}

/// iOS 用 UIActivityIndicatorView。
final class SystemSpinner extends StatelessWidget {
  const SystemSpinner({this.size = 20, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.primary;
    if (!_ios) {
      return SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: ink),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: UiKitView(
        viewType: 'onewifi/system_spinner',
        creationParams: {'color': ink.toARGB32()},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}