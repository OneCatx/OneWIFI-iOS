import 'package:flutter/material.dart';

import '../../../core/state/query_state.dart';
import '../domain/certificate.dart';
import '../state/certificate_controller.dart';
import 'widgets/certificate_card.dart';
import 'widgets/certificate_detail_dialog.dart';
import 'widgets/certificate_upload_dialog.dart';

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({
    super.key,
    this.controller,
    this.embedded = false,
  });

  final CertificateController? controller;
  final bool embedded;

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller?.loadCertificates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (widget.embedded) {
      if (controller == null) {
        return const Text('证书管理不可用');
      }
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _embedded(context, controller),
      );
    }
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('HTTPS Certificates'),
          elevation: 0,
        ),
        body: const Center(
          child: Text('Certificate manager is unavailable'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HTTPS Certificates'),
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.certificates;

          if (state.status == QueryStatus.loading &&
              (state.lastGoodData == null || state.lastGoodData!.isEmpty)) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == QueryStatus.failed &&
              (state.lastGoodData == null || state.lastGoodData!.isEmpty)) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load certificates'),
                  const SizedBox(height: 8),
                  Text(
                    state.failure?.kind.name ?? 'unknown',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: controller.loadCertificates,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadCertificates,
            child: _buildContent(context, controller),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadDialog(context, controller),
        icon: const Icon(Icons.add),
        label: const Text('Upload Certificate'),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    CertificateController controller,
  ) {
    final state = controller.certificates;
    final certificates = controller.items;
    final expiringCerts =
        certificates.where((c) => c.isExpiringSoon || c.isExpired).toList();

    return CustomScrollView(
      slivers: [
        if (expiringCerts.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildExpiryWarningBanner(context, expiringCerts.first),
          ),
        ],
        if (state.status == QueryStatus.failed && state.failure != null) ...[
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
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
                      state.failure!.kind.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (certificates.isEmpty) ...[
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 80,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Certificates',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload a custom certificate to secure your gateway',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final cert = certificates[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CertificateCard(
                      certificate: cert,
                      onTap: () => _showDetailDialog(context, controller, cert),
                    ),
                  );
                },
                childCount: certificates.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpiryWarningBanner(BuildContext context, Certificate cert) {
    final daysLeft = cert.daysUntilExpiry;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cert.isExpired
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            cert.isExpired ? Icons.error : Icons.warning,
            color: cert.isExpired
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cert.isExpired
                      ? 'Certificate Expired'
                      : 'Certificate Expiring Soon',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  cert.isExpired
                      ? 'Expired ${-daysLeft} days ago'
                      : 'Expires in $daysLeft days',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _embedded(BuildContext context, CertificateController controller) {
    final state = controller.certificates;
    final certificates = controller.items;
    if (state.status == QueryStatus.loading && certificates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.status == QueryStatus.failed && certificates.isEmpty)
          Text(state.failure?.kind.name ?? '加载失败'),
        if (certificates.isEmpty)
          const Text('还没有证书')
        else
          for (final cert in certificates)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CertificateCard(
                certificate: cert,
                onTap: () => _showDetailDialog(context, controller, cert),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showUploadDialog(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('上传证书'),
          ),
        ),
      ],
    );
  }

  void _showUploadDialog(
    BuildContext context,
    CertificateController controller,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => CertificateUploadDialog(
        onUpload: (certPem, keyPem) async {
          await controller.uploadCertificate(
            certificatePem: certPem,
            privateKeyPem: keyPem,
          );
        },
      ),
    );
  }

  void _showDetailDialog(
    BuildContext context,
    CertificateController controller,
    Certificate certificate,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => CertificateDetailDialog(
        certificate: certificate,
        onDelete: () async {
          await controller.deleteCertificate(certificate.id);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        onDownload: controller.downloadCertificatePem,
      ),
    );
  }
}
