import 'package:flutter/material.dart';

class CertificateUploadDialog extends StatefulWidget {
  final Future<void> Function(String certificatePem, String privateKeyPem)
      onUpload;

  const CertificateUploadDialog({
    super.key,
    required this.onUpload,
  });

  @override
  State<CertificateUploadDialog> createState() =>
      _CertificateUploadDialogState();
}

class _CertificateUploadDialogState extends State<CertificateUploadDialog> {
  final _certificateController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _certificateController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Certificate'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paste certificate and private key in PEM format',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _certificateController,
                decoration: const InputDecoration(
                  labelText: 'Certificate (PEM)',
                  hintText:
                      '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.file_copy),
                ),
                maxLines: 6,
                enabled: !_isUploading,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _privateKeyController,
                decoration: const InputDecoration(
                  labelText: 'Private Key (PEM)',
                  hintText:
                      '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                maxLines: 6,
                obscureText: true,
                enabled: !_isUploading,
                onChanged: (_) => setState(() {}),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canUpload && !_isUploading ? _handleUpload : null,
          child: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Upload'),
        ),
      ],
    );
  }

  bool get _canUpload {
    final cert = _certificateController.text.trim();
    final key = _privateKeyController.text.trim();
    return cert.isNotEmpty &&
        key.isNotEmpty &&
        _isValidPem(cert) &&
        _isValidPem(key);
  }

  bool _isValidPem(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith('-----BEGIN') && trimmed.contains('-----END');
  }

  Future<void> _handleUpload() async {
    final cert = _certificateController.text.trim();
    final key = _privateKeyController.text.trim();

    if (!_isValidPem(cert)) {
      setState(() {
        _errorMessage =
            'Invalid certificate format. Must start with -----BEGIN CERTIFICATE-----';
      });
      return;
    }

    if (!_isValidPem(key)) {
      setState(() {
        _errorMessage =
            'Invalid private key format. Must start with -----BEGIN PRIVATE KEY-----';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      await widget.onUpload(cert, key);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate uploaded successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isUploading = false;
      });
    }
  }
}
