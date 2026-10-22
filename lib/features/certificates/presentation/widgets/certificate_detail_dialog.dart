import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../domain/certificate.dart';

class CertificateDetailDialog extends StatefulWidget {
  final Certificate certificate;
  final Future<void> Function() onDelete;
  final Future<String> Function()? onDownload;

  const CertificateDetailDialog({
    super.key,
    required this.certificate,
    required this.onDelete,
    this.onDownload,
  });

  @override
  State<CertificateDetailDialog> createState() =>
      _CertificateDetailDialogState();
}

class _CertificateDetailDialogState extends State<CertificateDetailDialog> {
  bool _isDeleting = false;
  bool _isDownloading = false;

  @override
  Widget build(BuildContext context) {
    final cert = widget.certificate;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.shield, color: colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Certificate Details')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBanner(context, cert),
            const SizedBox(height: 24),
            _buildDetailRow(
              context,
              label: 'Common Name',
              value: cert.commonName,
              icon: Icons.public,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              label: 'Issuer',
              value: cert.issuer,
              icon: Icons.business,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              label: 'Valid From',
              value: DateFormat('MMM dd, yyyy HH:mm').format(cert.validFrom),
              icon: Icons.event,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              label: 'Valid To',
              value: DateFormat('MMM dd, yyyy HH:mm').format(cert.validTo),
              icon: Icons.event,
              valueColor: cert.isExpiringSoon || cert.isExpired
                  ? (cert.isExpired ? colorScheme.error : Colors.orange)
                  : null,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              label: 'Source',
              value: cert.source.displayName,
              icon: Icons.source,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              label: 'Fingerprint',
              value: cert.fingerprint,
              icon: Icons.fingerprint,
              copyable: true,
            ),
            if (cert.subjectAlternativeNames.isNotEmpty) ...[
              const Divider(height: 24),
              _buildDetailRow(
                context,
                label: 'Subject Alternative Names',
                value: cert.subjectAlternativeNames.join(', '),
                icon: Icons.dns,
              ),
            ],
            if (!cert.coversHost) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: colorScheme.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Certificate does not cover the current host',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
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
      actions: [
        if (cert.source == CertificateSource.custom)
          TextButton.icon(
            onPressed: _isDeleting ? null : _handleDelete,
            icon: _isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete),
            label: const Text('Delete'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
            ),
          ),
        if (widget.onDownload != null)
          TextButton.icon(
            onPressed: _isDownloading ? null : _handleDownload,
            icon: _isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: const Text('Download'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(BuildContext context, Certificate cert) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Color bgColor;
    Color fgColor;
    IconData icon;
    String status;

    if (cert.isExpired) {
      bgColor = colorScheme.errorContainer;
      fgColor = colorScheme.error;
      icon = Icons.error;
      status = 'Expired ${-cert.daysUntilExpiry} days ago';
    } else if (cert.isExpiringSoon) {
      bgColor = Colors.orange.withValues(alpha: 0.1);
      fgColor = Colors.orange;
      icon = Icons.warning;
      status = 'Expires in ${cert.daysUntilExpiry} days';
    } else {
      bgColor = Colors.green.withValues(alpha: 0.1);
      fgColor = Colors.green;
      icon = Icons.check_circle;
      status = 'Valid for ${cert.daysUntilExpiry} days';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: fgColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: textTheme.titleSmall?.copyWith(
                color: fgColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
    bool copyable = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: textTheme.bodyMedium?.copyWith(color: valueColor),
              ),
            ),
            if (copyable)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyToClipboard(context, value),
                tooltip: 'Copy',
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Certificate'),
        content: const Text(
          'Are you sure you want to delete this certificate? '
          'The gateway will revert to using a self-signed certificate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      await widget.onDelete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete certificate: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _handleDownload() async {
    final download = widget.onDownload;
    if (download == null || _isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final pem = await download();
      await Clipboard.setData(ClipboardData(text: pem));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate copied to clipboard'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download certificate: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }
}
