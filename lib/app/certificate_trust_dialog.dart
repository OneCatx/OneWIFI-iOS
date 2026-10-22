import 'package:flutter/material.dart';

import '../core/http/gateway_io_client.dart';
import '../design/widgets/glass_dialog.dart';

Future<void> showCertificateTrustDialog({
  required BuildContext context,
  required GatewayConnectionFactory connections,
  required Uri origin,
}) => showOneGlassPopup<void>(
  context: context,
  heightFactor: 0.64,
  builder: (_) =>
      _CertificateTrustForm(connections: connections, origin: origin),
);

final class _CertificateTrustForm extends StatefulWidget {
  const _CertificateTrustForm({
    required this.connections,
    required this.origin,
  });
  final GatewayConnectionFactory connections;
  final Uri origin;
  @override
  State<_CertificateTrustForm> createState() => _CertificateTrustFormState();
}

final class _CertificateTrustFormState extends State<_CertificateTrustForm> {
  final _fingerprint = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pin = await widget.connections.readFingerprint(widget.origin);
      if (!mounted) return;
      _fingerprint.text = pin ?? '';
    } catch (_) {
      if (!mounted) return;
      _error = '无法读取本机证书配置。';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.connections.setFingerprint(
        widget.origin,
        clear ? null : _fingerprint.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法保存本机证书配置，原配置未改变。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _fingerprint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('证书指纹', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(widget.origin.toString()),
      const SizedBox(height: 12),
      const Text(
        '普通 HTTPS 无需配置。自签证书请从可信的设备管理界面或管理员处核对完整 SHA-256 指纹。仅信任此地址的这张证书；换证书后需重新核对。',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('certificate-fingerprint'),
        controller: _fingerprint,
        enabled: !_loading && !_saving,
        minLines: 2,
        maxLines: 3,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'SHA-256（64 位十六进制）',
          errorText: _error,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _loading || _saving ? null : () => _save(),
        child: const Text('保存此证书指纹'),
      ),
      TextButton(
        onPressed: _loading || _saving ? null : () => _save(clear: true),
        child: const Text('清除指纹，恢复系统验证'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}
