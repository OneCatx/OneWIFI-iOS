/// MDD gateway API adapter (P1) + WEB path ledger (P2–P6).
/// OneWIFI strengths + MDD call base share this surface on mobile.
/// Canonical paths for the MDD-based gateway control plane and WEB 真源.
abstract final class GatewayApi {
  // Auth — WEB `server_auth.go` contract (Bearer session_token; CSRF skipped for Bearer-only)
  static const login = '/api/auth/login';
  static const logout = '/api/auth/logout';
  static const session = '/api/auth/session';
  @Deprecated('Use GatewayApi.session; WEB path is GET /api/auth/session')
  static const authStatus = session;

  // Lines / calls (MDD 旁路 — 主路径见下方 WEB sms/calls)
  static String instances() => '/api/instances';
  static String instance(String id) => '/api/instances/$id';
  static String status(String id) => '/api/instances/$id/status';
  static String softphone(String id) => '/api/instances/$id/softphone';
  static String softphoneWs(String id) => '/api/instances/$id/softphone/ws';
  static String dial(String id) => '/api/instances/$id/call';
  static String hangup(String id) => '/api/instances/$id/hangup';
  static String calls(String id) => '/api/instances/$id/calls';
  static String cellularCall(String id) => '/api/instances/$id/cellular-call';

  // SMS / MMS（MDD instance 路径；主路径用 smsContacts / smsThread / smsSendGlobal）
  @Deprecated('WEB SMS is /api/sms/*; use GatewayApi.smsSendGlobal')
  static String smsSend(String id) => '/api/instances/$id/sms/send';
  @Deprecated('WEB SMS threads are /api/sms/thread; use GatewayApi.smsThread')
  static String threads(String id) => '/api/instances/$id/messages/threads';
  @Deprecated('WEB has no instance MMS path; do not use for OneWIFI main')
  static String mmsSend(String id) => '/api/instances/$id/mms/send';

  // Devices — WEB `device_api*.go` / `device_api_dispatch.go` 真源
  static const dashboardHost = '/api/dashboard/host';
  static const dashboardDevices = '/api/dashboard/devices';
  static const devices = '/api/devices';
  static const devicesDiscovered = '/api/devices/discovered';
  static const devicesRescan = '/api/devices/actions/rescan';
  /// Bare id: PUT/PATCH/DELETE only. **No GET** (WEB 405). Detail → [deviceOverview].
  static String device(String id) => '/api/devices/$id';
  static String deviceOverview(String id) => '/api/devices/$id/overview';
  static String deviceStatus(String id) => '/api/devices/$id/status';
  static String deviceConfig(String id) => '/api/devices/$id/config';
  static String deviceNetwork(String id) => '/api/devices/$id/network';
  static String deviceVowifi(String id) => '/api/devices/$id/vowifi';
  static String deviceFlightMode(String id) => '/api/devices/$id/flight-mode';
  static String deviceRefresh(String id) => '/api/devices/$id/actions/refresh';
  static String deviceReboot(String id) => '/api/devices/$id/actions/reboot';
  static String deviceVowifiReconnect(String id) =>
      '/api/devices/$id/vowifi/actions/reconnect';
  @Deprecated('WEB has no /ims; use deviceOverview / vowifi')
  static String deviceIms(String id) => '/api/devices/$id/ims';
  @Deprecated('WEB path is /network not /cellular')
  static String deviceCellular(String id) => '/api/devices/$id/cellular';
  @Deprecated('WEB has no /hardware subpath')
  static String deviceHardware(String id) => '/api/devices/$id/hardware';

  // Calls — WEB `call_*.go` 真源（主路径；iOS 另有 CallKit/PushKit）
  // Templates with `{id}` match HttpTransport.pathParameters.
  static const callsEvents = '/api/calls/events';
  static const callsPush = '/api/calls/push';
  static const callsMediaCapabilities = '/api/calls/media/capabilities';
  static const deviceCalls = '/api/devices/{id}/calls';
  static const deviceCallsDial = '/api/devices/{id}/calls/dial';
  static const deviceCallsAnswer = '/api/devices/{id}/calls/answer';
  static const deviceCallsHangup = '/api/devices/{id}/calls/hangup';
  static const deviceCallsDtmf = '/api/devices/{id}/calls/dtmf';
  static const deviceCallsMedia = '/api/devices/{id}/calls/media';
  static const deviceCallsMediaTicket = '/api/devices/{id}/calls/media-ticket';
  static const deviceCallsHistory = '/api/devices/{id}/calls/history';
  static const deviceCallsHistoryExport = '/api/devices/{id}/calls/history/export';
  static const deviceCallsWebRtc = '/api/devices/{id}/calls/webrtc';

  // SMS — WEB `sms_api*.go`（全局；非 MDD /api/instances/{id}/sms*）
  static const smsContacts = '/api/sms/contacts';
  static const smsThread = '/api/sms/thread';
  static const smsSendGlobal = '/api/sms/send';
  static const smsExport = '/api/sms/export';
  static const smsMessage = '/api/sms/messages/{id}';

  // OneTools / APNs — WEB `onetools_api.go`（配对 Bearer，非 session）
  static const onetoolsSmsStream = '/api/onetools/sms/stream';
  static const onetoolsIosPushEndpoint = '/api/onetools/ios/push-endpoint';
  static const onetoolsIosPushEndpointAck =
      '/api/onetools/ios/push-endpoint/ack';

  // Settings / license / HTTPS — WEB `settings_api*` · `https_settings.go` · `license_api.go`
  static const settingsPreferences = '/api/settings/preferences';
  static const settingsNotifications = '/api/settings/notifications';
  static const settingsNotificationsTest =
      '/api/settings/notifications/{channel}/test';
  static const settingsPassword = '/api/settings/password';
  static const settingsSecurity = '/api/settings/security';
  static const settingsHttps = '/api/settings/https';
  static const settingsHttpsCertificate = '/api/settings/https/certificate';
  static const settingsHttpsCustom = '/api/settings/https/custom';
  static const settingsHttpsReissue = '/api/settings/https/reissue';
  static const settingsDeveloper = '/api/settings/developer';
  static const settingsSms = '/api/settings/sms';
  static const settingsVowifi = '/api/settings/vowifi';
  static const settingsCalls = '/api/settings/calls';
  static const systemInfo = '/api/system/info';
  static const systemUpdateCheck = '/api/system/update/check';
  static const systemUpdateApply = '/api/system/update/apply';
  static const health = '/api/health';
  static const license = '/api/license';

  // eSIM — WEB `esim_api*.go` · `esim_notifications_api.go`
  // Templates with `{id}`/`{iccid}`/`{nid}`/`{seq}` match HttpTransport.pathParameters.
  static const deviceEsim = '/api/devices/{id}/esim';
  static const deviceEsimProfiles = '/api/devices/{id}/esim/profiles';
  static const deviceEsimProfile = '/api/devices/{id}/esim/profiles/{iccid}';
  static const deviceEsimNotifications = '/api/devices/{id}/esim/notifications';
  static const deviceEsimNotificationRetry =
      '/api/devices/{id}/esim/notifications/{seq}/actions/retry';
  static const deviceEsimUserNotifications =
      '/api/devices/{id}/esim/user-notifications';
  static const deviceEsimUserNotification =
      '/api/devices/{id}/esim/user-notifications/{nid}';
  static const deviceEsimSwitch = '/api/devices/{id}/esim/actions/switch';
  static const deviceEsimDisable = '/api/devices/{id}/esim/actions/disable';
  static const deviceEsimDownload = '/api/devices/{id}/esim/actions/download';
  @Deprecated('Use deviceEsimProfiles')
  static String esimProfiles(String deviceId) =>
      '/api/devices/$deviceId/esim/profiles';

  // Upstream proxy — WEB `proxy_api*.go`（网关出站；非本地 Mihomo Tab）
  // Templates with `{id}`/`{cc}` match HttpTransport.pathParameters.
  static const upstreamProxies = '/api/upstream-proxies';
  static const upstreamProxyItem = '/api/upstream-proxies/{id}';
  static const upstreamProxyProbeActionPath =
      '/api/upstream-proxies/{id}/actions/probe';
  static String upstreamProxy(String id) => '/api/upstream-proxies/$id';
  static String upstreamProxyProbeAction(String id) =>
      '/api/upstream-proxies/$id/actions/probe';
  static const upstreamProxyProbe = '/api/upstream-proxy-probe';
  static const upstreamProxyCountries = '/api/upstream-proxy-countries';
  static const upstreamProxyCountryRules = '/api/upstream-proxy-country-rules';
  static const upstreamProxyCountryRuleItem =
      '/api/upstream-proxy-country-rules/{cc}';
  static String upstreamProxyCountryRule(String cc) =>
      '/api/upstream-proxy-country-rules/$cc';
  static const upstreamProxyProfileBindings =
      '/api/upstream-proxy-profile-bindings';

  // Export proxy — WEB `export_proxy_api.go`（developer mode）
  static const exportProxies = '/api/export-proxies';
  static const exportProxiesStatus = '/api/export-proxies/status';
  static const exportProxyItem = '/api/export-proxies/{id}';
  static String exportProxy(String id) => '/api/export-proxies/$id';

  // Automatic tasks — WEB `automatic_tasks_api.go`
  static const automaticTasks = '/api/automatic-tasks';
  static const automaticTaskRuns = '/api/automatic-tasks/runs';
  static const automaticTask = '/api/automatic-tasks/{id}';
  static const automaticTaskRun = '/api/automatic-tasks/{id}/run';

  // Logs / loghub — WEB `general_api_logs.go`
  static const logsHistory = '/api/logs/history';
  static const logsStream = '/api/logs/stream';

  // Card policy / eUICC catalog — WEB `settings_api_card.go` · `general_api.go`
  static const cardsPolicies = '/api/cards/policies';
  static const cardPolicy = '/api/cards/{iccid}/policy';
  static const euiccCatalog = '/api/euicc-catalog';

  // Extensions — WEB `extensions_api.go`（P6 增量；设置下钻，非底栏）
  // `extensionItem` uses `{id}` for pathParameters（avoid Dart keyword `extension`）。
  static const extensions = '/api/extensions';
  static const extensionsInstallUrl = '/api/extensions/install-url';
  static const extensionsUpload = '/api/extensions/upload';
  static const extensionItem = '/api/extensions/{id}';
  static String extensionById(String id) => '/api/extensions/$id';

  static const notifySettings = settingsNotifications;
  static const carrierProfiles = '/api/carrier/profiles';
}

/// HTTP header names used by gateway control.
/// CSRF must match WEB `csrfHeaderName` (`X-CSRF-Token`).
abstract final class GatewayHeaders {
  static const csrf = 'X-CSRF-Token';
  static const contentType = 'Content-Type';
  static const accept = 'Accept';
}
