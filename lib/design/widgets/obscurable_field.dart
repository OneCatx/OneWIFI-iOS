import 'package:flutter/material.dart';
import 'system_controls.dart';

/// 敏感输入：默认蒙住，右侧眼睛可揭开。
final class ObscurableField extends StatefulWidget {
  const ObscurableField({
    required this.controller,
    required this.labelText,
    this.hintText,
    this.enabled = true,
    this.autocorrect = false,
    this.keyboardType,
    this.revealLabel,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool enabled;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final String? revealLabel;

  @override
  State<ObscurableField> createState() => _ObscurableFieldState();
}

final class _ObscurableFieldState extends State<ObscurableField> {
  bool _obscured = true;

  String get _revealName => widget.revealLabel ?? widget.labelText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: widget.autocorrect,
      enableSuggestions: false,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _obscured ? '显示$_revealName' : '隐藏$_revealName',
          icon: SystemIcon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}
