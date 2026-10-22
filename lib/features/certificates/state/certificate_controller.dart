import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/certificate_repository.dart';
import '../domain/certificate.dart';

/// Controller for HTTPS certificate management.
final class CertificateController extends RequestNotifier {
  CertificateController({
    required this.repository,
    required RequestRegistry requestRegistry,
  })  : _read = RequestSlot(requestRegistry, _loadKey),
        _upload = RequestSlot(requestRegistry, 'certificate.upload'),
        _delete = RequestSlot(requestRegistry, 'certificate.delete'),
        _download = RequestSlot(requestRegistry, 'certificate.download');

  static const String _loadKey = 'certificate.load';

  final CertificateRepository repository;
  final RequestSlot _read;
  final RequestSlot _upload;
  final RequestSlot _delete;
  final RequestSlot _download;

  QueryState<List<Certificate>> _certificates =
      const QueryState<List<Certificate>>.initial(key: _loadKey);
  ActionState _uploadAction = const ActionState.idle();
  ActionState _deleteAction = const ActionState.idle();
  ActionState _downloadAction = const ActionState.idle();

  QueryState<List<Certificate>> get certificates => _certificates;

  /// Convenience view of the last-good / empty certificate list.
  List<Certificate> get items =>
      _certificates.lastGoodData ?? const <Certificate>[];

  ActionState get uploadAction => _uploadAction;
  ActionState get deleteAction => _deleteAction;
  ActionState get downloadAction => _downloadAction;

  @override
  List<RequestSlot> get slots =>
      <RequestSlot>[_read, _upload, _delete, _download];

  /// Loads the certificate list (0–1 entries in the current backend).
  Future<void> loadCertificates() => runQuery<List<Certificate>>(
        slot: _read,
        current: () => _certificates,
        set: _setCertificates,
        fetch: (ticket) => repository.getCertificates(
          cancellation: ticket.cancellation,
        ),
        isEmpty: (value) => value.isEmpty,
      );

  /// Uploads a custom certificate and replaces the list with the new entry.
  Future<bool> uploadCertificate({
    required String certificatePem,
    required String privateKeyPem,
  }) {
    return runAction<Certificate>(
      slot: _upload,
      current: () => _uploadAction,
      set: _setUploadAction,
      request: (ticket) => repository.uploadCertificate(
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (certificate, ticket) {
        _setCertificates(
          QueryState<List<Certificate>>.data(
            data: <Certificate>[certificate],
            key: _loadKey,
          ),
        );
        return const ActionState.succeeded();
      },
    );
  }

  /// Deletes the custom certificate (reverts to self-signed) and reloads.
  Future<bool> deleteCertificate(String certificateId) async {
    final ok = await runAction<void>(
      slot: _delete,
      current: () => _deleteAction,
      set: _setDeleteAction,
      key: certificateId,
      request: (ticket) => repository.deleteCertificate(
        certificateId,
        cancellation: ticket.cancellation,
      ),
    );
    if (ok) {
      await loadCertificates();
    }
    return ok;
  }

  /// Downloads the current certificate PEM from the gateway.
  ///
  /// Returns the PEM text on success. Throws [CertificateRepositoryException]
  /// (or the underlying failure wrapped by the repository) on error so the UI
  /// can surface a snackbar.
  Future<String> downloadCertificatePem() async {
    String? pem;
    final ok = await runAction<String>(
      slot: _download,
      current: () => _downloadAction,
      set: _setDownloadAction,
      request: (ticket) => repository.downloadCertificatePem(
        cancellation: ticket.cancellation,
      ),
      onSuccess: (result, ticket) {
        pem = result;
        return const ActionState.succeeded();
      },
    );
    if (!ok || pem == null) {
      final failure =
          _downloadAction.knownFailure ?? _downloadAction.unknownOutcome;
      throw CertificateRepositoryException(
        failure == null
            ? 'Failed to download certificate'
            : 'Failed to download certificate: ${failure.kind.name}',
      );
    }
    return pem!;
  }

  void _setCertificates(QueryState<List<Certificate>> next) =>
      publish(() => _certificates = next);

  void _setUploadAction(ActionState next) =>
      publish(() => _uploadAction = next);

  void _setDeleteAction(ActionState next) =>
      publish(() => _deleteAction = next);

  void _setDownloadAction(ActionState next) =>
      publish(() => _downloadAction = next);
}
