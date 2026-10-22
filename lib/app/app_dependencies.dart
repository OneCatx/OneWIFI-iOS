import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/base_url_store.dart';
import '../core/config/gateway_api.dart';
import '../core/http/gateway_io_client.dart';
import '../core/http/http_transport.dart';
import '../core/http/request_registry.dart';
import '../core/security/secure_token_store.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/state/session_controller.dart';
import '../features/automation/data/automation_api.dart';
import '../features/automation/data/automation_repository.dart';
import '../features/automation/state/automation_controller.dart';
import '../features/calls/data/call_push_registrar.dart';
import '../features/calls/data/calls_api.dart';
import '../features/calls/data/calls_repository.dart';
import '../features/calls/data/ios_call_push.dart';
import '../features/calls/data/native_call_session.dart';
import '../features/calls/state/call_push_binding.dart';
import '../features/calls/state/call_session_binding.dart';
import '../features/calls/state/calls_controller.dart';
import '../features/certificates/data/certificate_api.dart';
import '../features/certificates/data/certificate_repository.dart';
import '../features/certificates/state/certificate_controller.dart';
import '../features/devices/data/device_api.dart';
import '../features/devices/data/device_repository.dart';
import '../features/devices/state/device_detail_controller.dart';
import '../features/devices/state/device_list_controller.dart';
import '../features/esim/data/esim_api.dart';
import '../features/esim/data/esim_repository.dart';
import '../features/esim/domain/euicc_catalog.dart';
import '../features/esim/state/esim_controller.dart';
import '../features/export_proxy/data/export_proxy_api.dart';
import '../features/export_proxy/data/export_proxy_repository.dart';
import '../features/export_proxy/state/export_proxy_controller.dart';
import '../features/extensions/data/extensions_api.dart';
import '../features/extensions/data/extensions_repository.dart';
import '../features/extensions/state/extensions_controller.dart';
import '../features/logs/data/logs_api.dart';
import '../features/logs/data/logs_repository.dart';
import '../features/logs/state/logs_controller.dart';
import '../features/overview/data/overview_api.dart';
import '../features/overview/data/overview_repository.dart';
import '../features/overview/state/overview_controller.dart';
import '../features/proxy/data/mihomo_backend_store.dart';
import '../features/proxy/data/mihomo_client.dart';
import '../features/proxy/data/proxy_repository.dart';
import '../features/proxy/state/mihomo_connection_controller.dart';
import '../features/proxy/state/proxy_controller.dart';
import '../features/settings/data/product_license_store.dart';
import '../features/settings/data/settings_api.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/sms/data/ios_apns_bridge.dart';
import '../features/sms/data/ios_push_endpoint_client.dart';
import '../features/sms/data/remote_otp_pairing_store.dart';
import '../features/sms/data/remote_otp_stream_client.dart';
import '../features/sms/data/sms_api.dart';
import '../features/sms/data/sms_repository.dart';
import '../features/sms/domain/sms.dart';
import '../features/sms/state/remote_otp_controller.dart';
import '../features/sms/state/sms_controller.dart';
import '../features/upstream/data/upstream_api.dart';
import '../features/upstream/data/upstream_repository.dart';
import '../features/upstream/state/upstream_controller.dart';

final class AppDependencies {
  factory AppDependencies({
    http.BaseClient? httpClient,
    BaseUrlStore? baseUrlStore,
    TokenStore? tokenStore,
    ProductLicenseStore? productLicenseStore,
    SmsOtpSink? otpSink,
    RemoteOtpPairingStore? remoteOtpStore,
    MihomoBackendStore? mihomoBackendStore,
  }) {
    final http.BaseClient client = httpClient ?? createGatewayIoClient();
    final origins =
        baseUrlStore ?? CachedBaseUrlStore(SharedPreferencesBaseUrlStore());
    final tokens = tokenStore ?? CachedTokenStore(SecureTokenStore());
    final requests = RequestRegistry();
    late final SessionController session;
    final transport = HttpTransport(
      client: client,
      originProvider: origins.read,
      tokenProvider: tokens.read,
      sessionEpoch: () => session.sessionEpoch,
      onUnauthorized: (capturedEpoch) => session.expireIfCurrent(capturedEpoch),
    );
    final authRepository = DefaultAuthRepository(
      api: AuthApi(transport),
      tokenStore: tokens,
      originProvider: origins.read,
    );
    session = SessionController(
      repository: authRepository,
      tokenStore: tokens,
      baseUrlStore: origins,
      requestRegistry: requests,
      connections: client is GatewayConnectionFactory ? client : null,
    );
    final callsApi = CallsApi(
      transport,
      socketConnector: client is GatewayConnectionFactory
          ? client.openWebSocket
          : null,
    );
    final nativeCalls = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? (CallSessionBinding(
            native: const IOSNativeCallSession(),
            tokenProvider: tokens.read,
            fingerprintProvider: client is GatewayConnectionFactory
                ? client.readFingerprint
                : (_) async => null,
            trustChanges: client is GatewayConnectionFactory ? client : null,
          )..attach(session))
        : null;
    // 通话推送登记与通话会话是两件事：登记失败绝不能牵连通话界面，反过来
    // 会话投影失败也不该让手机不再被推送唤醒。
    final callPush = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? (CallPushBinding(
            tokens: IosCallPushTokens(),
            registrar: GatewayCallPushRegistrar(transport),
          )..attach(session))
        : null;
    final source = mihomoBackendStore ?? createMihomoBackendStore();
    final mihomoStore = source is ObservableMihomoBackendStore
        ? source
        : CachedMihomoBackendStore(source);
    final mihomoClient = MihomoClient(
      client: client,
      backendProvider: () async {
        final backend = await mihomoStore.read();
        if (backend == null) {
          throw const FormatException('未连接 Mihomo');
        }
        return backend;
      },
    );
    return AppDependencies._(
      client,
      requests,
      session,
      DefaultOverviewRepository(OverviewApi(transport)),
      DefaultDeviceRepository(DeviceApi(transport)),
      DefaultEsimRepository(EsimApi(transport)),
      DefaultSmsRepository(SmsApi(transport)),
      DefaultCallsRepository(callsApi),
      origins.read,
      tokens.read,
      DefaultProxyRepository(mihomoClient),
      mihomoStore,
      mihomoClient,
      DefaultAutomationRepository(AutomationApi(transport)),
      DefaultLogsRepository(LogsApi(transport)),
      DefaultExtensionsRepository(ExtensionsApi(transport)),
      DefaultUpstreamRepository(UpstreamApi(transport)),
      DefaultExportProxyRepository(ExportProxyApi(transport)),
      DefaultSettingsRepository(SettingsApi(transport)),
      DefaultCertificateRepository(CertificateApi(transport)),
      productLicenseStore ?? createProductLicenseStore(),
      otpSink,
      remoteOtpStore ?? SecureRemoteOtpPairingStore(),
      () => syncEuiccCatalog(
        () => transport.sendJson(
          method: 'GET',
          routeTemplate: GatewayApi.euiccCatalog,
        ),
      ),
      nativeCalls,
      callPush,
    );
  }

  AppDependencies._(
    this._httpClient,
    this._requestRegistry,
    this.sessionController,
    this._overviewRepository,
    this._deviceRepository,
    this._esimRepository,
    this._smsRepository,
    this._callsRepository,
    this._originProvider,
    this._tokenProvider,
    this._proxyRepository,
    this._mihomoStore,
    this._mihomoClient,
    this._automationRepository,
    this._logsRepository,
    this._extensionsRepository,
    this._upstreamRepository,
    this._exportProxyRepository,
    this._settingsRepository,
    this._certificateRepository,
    this._licenseStore,
    this._otpSink,
    this._remoteOtpStore,
    this._syncEuiccCatalog,
    this._nativeCalls,
    this._callPush,
  );

  final http.BaseClient _httpClient;
  final RequestRegistry _requestRegistry;
  final OverviewRepository _overviewRepository;
  final DeviceRepository _deviceRepository;
  final EsimRepository _esimRepository;
  final SmsRepository _smsRepository;
  final CallsRepository _callsRepository;
  final Future<Uri> Function() _originProvider;
  final Future<String?> Function(Uri origin) _tokenProvider;
  final ProxyRepository _proxyRepository;
  final MihomoBackendStore _mihomoStore;
  final MihomoClient _mihomoClient;
  final AutomationRepository _automationRepository;
  final LogsRepository _logsRepository;
  final ExtensionsRepository _extensionsRepository;
  final UpstreamRepository _upstreamRepository;
  final ExportProxyRepository _exportProxyRepository;
  final SettingsRepository _settingsRepository;
  final CertificateRepository _certificateRepository;
  final ProductLicenseStore _licenseStore;
  final SmsOtpSink? _otpSink;
  final RemoteOtpPairingStore _remoteOtpStore;
  final Future<void> Function() _syncEuiccCatalog;
  final CallSessionBinding? _nativeCalls;
  final CallPushBinding? _callPush;
  final SessionController sessionController;
  bool _disposed = false;

  OverviewController createOverviewController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return OverviewController(
      repository: _overviewRepository,
      requestRegistry: _requestRegistry,
    );
  }

  DeviceListController createDeviceListController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return DeviceListController(
      repository: _deviceRepository,
      requestRegistry: _requestRegistry,
      overviewLoader: _overviewLoader,
      catalogSync: _syncEuiccCatalog,
    );
  }

  /// eUICC 总览读取只在真实仓储上存在（接口不暴露，测试假实现不必跟）。
  EuiccOverviewLoader? get _overviewLoader {
    final repository = _esimRepository;
    if (repository is! DefaultEsimRepository) return null;
    return repository.fetchOverview;
  }

  DeviceDetailController createDeviceDetailController(String deviceId) {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return DeviceDetailController(
      deviceId: deviceId,
      repository: _deviceRepository,
      requestRegistry: _requestRegistry,
    );
  }

  EsimController createEsimController(String deviceId) {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return EsimController(
      deviceId: deviceId,
      repository: _esimRepository,
      requestRegistry: _requestRegistry,
      overviewLoader: _overviewLoader,
    );
  }

  SmsController createSmsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    final remoteOtp = RemoteOtpController(
      store: _remoteOtpStore,
      streamClient: RemoteOtpStreamClient(_httpClient),
      pushClient: IosPushEndpointClient(_httpClient),
      apns: IosApnsBridge(),
      otpSink: _otpSink,
      pollingOriginProvider: _originProvider,
    );
    remoteOtp.activity.attach(sessionController);
    return SmsController(
      repository: _smsRepository,
      requestRegistry: _requestRegistry,
      otpSink: _otpSink,
      remoteOtp: remoteOtp,
    );
  }

  CallsController createCallsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return CallsController(
      repository: _callsRepository,
      originProvider: _originProvider,
      tokenProvider: _tokenProvider,
      requestRegistry: _requestRegistry,
      nativeCalls: _nativeCalls,
    );
  }

  ProxyController createProxyController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return ProxyController(
      repository: _proxyRepository,
      requestRegistry: _requestRegistry,
      backendStore: _mihomoStore,
    );
  }

  MihomoConnectionController createMihomoConnectionController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return MihomoConnectionController(
      store: _mihomoStore,
      client: _mihomoClient,
      requestRegistry: _requestRegistry,
      connections: _httpClient is GatewayConnectionFactory ? _httpClient : null,
    );
  }

  AutomationController createAutomationController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return AutomationController(
      repository: _automationRepository,
      requestRegistry: _requestRegistry,
    );
  }

  LogsController createLogsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return LogsController(
      repository: _logsRepository,
      requestRegistry: _requestRegistry,
    );
  }

  ExtensionsController createExtensionsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return ExtensionsController(
      repository: _extensionsRepository,
      requestRegistry: _requestRegistry,
    );
  }

  UpstreamController createUpstreamController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return UpstreamController(
      repository: _upstreamRepository,
      requestRegistry: _requestRegistry,
    );
  }

  ExportProxyController createExportProxyController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return ExportProxyController(
      repository: _exportProxyRepository,
      requestRegistry: _requestRegistry,
    );
  }

  SettingsController createSettingsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return SettingsController(
      repository: _settingsRepository,
      licenseStore: _licenseStore,
      requestRegistry: _requestRegistry,
    );
  }

  CertificateController createCertificateController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return CertificateController(
      repository: _certificateRepository,
      requestRegistry: _requestRegistry,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestRegistry.cancelAll();
    _nativeCalls?.dispose();
    _callPush?.dispose();
    sessionController.dispose();
    _httpClient.close();
  }
}
