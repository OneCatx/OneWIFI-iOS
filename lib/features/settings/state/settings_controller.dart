import '../../../core/http/request_registry.dart';
import '../../../core/http/request_slot.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../core/state/request_notifier.dart';
import '../data/product_license_store.dart';
import '../data/settings_repository.dart';
import '../domain/gateway_settings.dart';

/// Manages gateway settings and system configuration.
///
/// This controller handles loading, updating, and persisting gateway settings including:
/// - UI language preferences
/// - Notification channel configurations
/// - Security and access policies
/// - HTTPS certificate settings
/// - Data quota management
/// - Product licensing
/// - SMS modem settings
/// - VoWiFi (Voice over WiFi) MTU settings
///
/// Each settings category has its own action state to track pending operations.
/// Unlike the Android version, this iOS variant omits system update functionality.
final class SettingsController extends RequestNotifier {
  /// Creates a [SettingsController] with the specified dependencies.
  ///
  /// Parameters:
  /// - [repository]: Repository for settings operations
  /// - [licenseStore]: Local storage for product license
  /// - [requestRegistry]: Registry for tracking and cancelling requests
  SettingsController({
    required this.repository,
    required this.licenseStore,
    required RequestRegistry requestRegistry,
  }) : _read = RequestSlot(requestRegistry, 'settings.load'),
       _language = RequestSlot(requestRegistry, 'settings.language'),
       _notify = RequestSlot(requestRegistry, 'settings.notify'),
       _test = RequestSlot(requestRegistry, 'settings.notify.test'),
       _password = RequestSlot(requestRegistry, 'settings.password'),
       _security = RequestSlot(requestRegistry, 'settings.security'),
       _https = RequestSlot(requestRegistry, 'settings.https'),
       _httpsUpload = RequestSlot(requestRegistry, 'settings.https.upload'),
       _httpsDelete = RequestSlot(requestRegistry, 'settings.https.delete'),
       _httpsReissue = RequestSlot(requestRegistry, 'settings.https.reissue'),
       _quota = RequestSlot(requestRegistry, 'settings.quota'),
       _license = RequestSlot(requestRegistry, 'settings.license'),
       _smsModem = RequestSlot(requestRegistry, 'settings.sms'),
       _vowifiMtu = RequestSlot(requestRegistry, 'settings.vowifi');

  /// Minimum required password length for gateway access.
  static const int minPasswordLength = 10;

  final SettingsRepository repository;
  final ProductLicenseStore licenseStore;
  final RequestSlot _read;
  final RequestSlot _language;
  final RequestSlot _notify;
  final RequestSlot _test;
  final RequestSlot _password;
  final RequestSlot _security;
  final RequestSlot _https;
  final RequestSlot _httpsUpload;
  final RequestSlot _httpsDelete;
  final RequestSlot _httpsReissue;
  final RequestSlot _quota;
  final RequestSlot _license;
  final RequestSlot _smsModem;
  final RequestSlot _vowifiMtu;

  QueryState<SettingsSnapshot> _snapshot =
      const QueryState<SettingsSnapshot>.initial(key: 'settings.load');
  ActionState _languageAction = const ActionState.idle();
  ActionState _notifyAction = const ActionState.idle();
  ActionState _testAction = const ActionState.idle();
  ActionState _passwordAction = const ActionState.idle();
  ActionState _securityAction = const ActionState.idle();
  ActionState _httpsAction = const ActionState.idle();
  ActionState _httpsUploadAction = const ActionState.idle();
  ActionState _httpsDeleteAction = const ActionState.idle();
  ActionState _httpsReissueAction = const ActionState.idle();
  ActionState _quotaAction = const ActionState.idle();
  ActionState _licenseAction = const ActionState.idle();
  ActionState _smsModemAction = const ActionState.idle();
  ActionState _vowifiMtuAction = const ActionState.idle();
  NotifyChannel? _testingChannel;
  String _notice = '';
  bool _noticeError = false;
  int _noticeSeq = 0;
  bool _passwordChanged = false;
  bool _loadAttempted = false;
  bool _notificationsLoaded = false;
  bool _securityLoaded = false;
  final Set<NotifyChannel> _notifyDirty = <NotifyChannel>{};
  final Map<NotifyChannel, int> _notifyRevisions = <NotifyChannel, int>{};
  final Map<_SettingsPart, int> _partRevisions = <_SettingsPart, int>{};

  /// Current query state for the settings snapshot.
  QueryState<SettingsSnapshot> get snapshot => _snapshot;
  
  /// Current settings data, or default if not loaded.
  SettingsSnapshot get data =>
      _snapshot.lastGoodData ?? const SettingsSnapshot();
      
  /// Action state for language update operations.
  ActionState get languageAction => _languageAction;
  
  /// Action state for notification configuration operations.
  ActionState get notifyAction => _notifyAction;
  
  /// Action state for notification test operations.
  ActionState get testAction => _testAction;
  
  /// Action state for password change operations.
  ActionState get passwordAction => _passwordAction;
  
  /// Action state for security policy operations.
  ActionState get securityAction => _securityAction;
  
  /// Action state for HTTPS certificate operations.
  ActionState get httpsAction => _httpsAction;
  
  /// Action state for HTTPS certificate upload operations.
  ActionState get httpsUploadAction => _httpsUploadAction;
  
  /// Action state for HTTPS certificate delete operations.
  ActionState get httpsDeleteAction => _httpsDeleteAction;
  
  /// Action state for HTTPS certificate reissue operations.
  ActionState get httpsReissueAction => _httpsReissueAction;
  
  /// Action state for quota management operations.
  ActionState get quotaAction => _quotaAction;
  
  /// Action state for license operations.
  ActionState get licenseAction => _licenseAction;
  
  /// Action state for SMS modem settings operations.
  ActionState get smsModemAction => _smsModemAction;
  
  /// Action state for VoWiFi MTU settings operations.
  ActionState get vowifiMtuAction => _vowifiMtuAction;
  NotifyChannel? get testingChannel => _testingChannel;
  String get notice => _notice;
  bool get noticeError => _noticeError;
  int get noticeSeq => _noticeSeq;
  bool get passwordChanged => _passwordChanged;

  @override
  List<RequestSlot> get slots => <RequestSlot>[
    _read,
    _language,
    _notify,
    _test,
    _password,
    _security,
    _https,
    _httpsUpload,
    _httpsDelete,
    _httpsReissue,
    _quota,
    _license,
    _smsModem,
    _vowifiMtu,
  ];

  Future<void> load() async {
    if (isDisposed) return;
    _loadAttempted = true;
    final ticket = _read.begin();
    final revisions = Map<_SettingsPart, int>.of(_partRevisions);
    final previous = _snapshot.lastGoodData;
    _setSnapshot(QueryState.pending(previous: previous, key: _read.key));
    try {
      // 每节读什么、叫什么名字只在这里登记一次：并发读取、结果合并、失败文案
      // 都按 `part` 索引，不再靠 `results[i]` 的位置对齐——位置一旦错位，
      // 报出来的节名和实际坏掉的节就会对不上。
      final reads = <({_SettingsPart part, Future<Object?> Function() read})>[
        (
          part: _SettingsPart.language,
          read: () => repository.fetchPreferences(
            cancellation: ticket.cancellation,
          ),
        ),
        (
          part: _SettingsPart.info,
          read: () => repository.fetchSystemInfo(
            cancellation: ticket.cancellation,
          ),
        ),
        (
          part: _SettingsPart.notifications,
          read: () => repository.fetchNotifications(
            cancellation: ticket.cancellation,
          ),
        ),
        (
          part: _SettingsPart.security,
          read: () => repository.fetchSecurity(
            cancellation: ticket.cancellation,
          ),
        ),
        (part: _SettingsPart.license, read: licenseStore.read),
        (
          part: _SettingsPart.smsModem,
          read: () => repository.fetchSmsModemSettings(
            cancellation: ticket.cancellation,
          ),
        ),
        (
          part: _SettingsPart.gatewayLicense,
          read: () => repository.fetchGatewayLicense(
            cancellation: ticket.cancellation,
          ),
        ),
        (
          part: _SettingsPart.vowifiMtu,
          read: () => repository.fetchVowifiSettings(
            cancellation: ticket.cancellation,
          ),
        ),
      ];
      final results = await Future.wait(reads.map(
        (read) => _capture(read.part, read.read()),
      ));
      if (!ticket.isCurrent) return;
      final byPart =
          <_SettingsPart, ({_SettingsPart part, Object? value, Object? error})>{
            for (final result in results) result.part: result,
          };
      T? loaded<T>(_SettingsPart part) => byPart[part]?.value as T?;
      bool failed(_SettingsPart part) => byPart[part]?.error != null;
      var next = (previous ?? const SettingsSnapshot()).copyWith(
        language: loaded<UiLanguage>(_SettingsPart.language),
        info: loaded<SystemInfo>(_SettingsPart.info),
        notifications: loaded<NotificationSettings>(_SettingsPart.notifications),
        security: loaded<AccessPolicy>(_SettingsPart.security),
        license: loaded<ProductLicense>(_SettingsPart.license),
        smsModem: loaded<SmsModemSettings>(_SettingsPart.smsModem),
        gatewayLicense: loaded<GatewayLicenseStatus>(
          _SettingsPart.gatewayLicense,
        ),
        vowifiMtu: loaded<VowifiMtuSettings>(_SettingsPart.vowifiMtu),
        clearGatewayLicense:
            !failed(_SettingsPart.gatewayLicense) &&
            loaded<GatewayLicenseStatus>(_SettingsPart.gatewayLicense) == null,
      );
      if (next.info.developer) {
        final https = await _ignore(
          repository.fetchHttps(cancellation: ticket.cancellation),
        );
        final quota = await _ignore(
          repository.fetchDeveloper(cancellation: ticket.cancellation),
        );
        if (!ticket.isCurrent) return;
        next = next.copyWith(
          https: https,
          quota: quota,
          clearHttps: https == null,
          clearQuota: quota == null,
        );
      } else {
        next = next.copyWith(clearHttps: true, clearQuota: true);
      }
      if (!ticket.isCurrent) return;
      if (!_changedSince(_SettingsPart.notifications, revisions)) {
        _notificationsLoaded = !failed(_SettingsPart.notifications);
        var notifications = next.notifications;
        for (final channel in _notifyDirty) {
          notifications = notifications.replacing(
            channel,
            data.notifications.of(channel),
          );
        }
        next = next.copyWith(notifications: notifications);
      }
      if (!_changedSince(_SettingsPart.security, revisions)) {
        _securityLoaded = !failed(_SettingsPart.security);
      }
      next = _mergeLoaded(next, revisions);
      final failedParts = <_SettingsPart>[
        for (final result in results)
          if (result.error != null) result.part,
      ];
      if (failedParts.isNotEmpty) {
        _setSnapshot(
          QueryState.failedAfter(
            byPart[failedParts.first]!.error!,
            previous: next,
            key: _read.key,
          ),
        );
        final coreFailed =
            failed(_SettingsPart.language) &&
            failed(_SettingsPart.info) &&
            failed(_SettingsPart.notifications);
        _setNotice(
          coreFailed
              ? '无法读取设置'
              : '部分设置读取失败：${failedParts.map((part) => part.label).join('、')}',
          error: true,
        );
      } else {
        _setSnapshot(
          QueryState<SettingsSnapshot>.data(data: next, key: _read.key),
        );
      }
    } catch (error) {
      if (!ticket.isCurrent) return;
      _setSnapshot(
        QueryState.failedAfter(error, previous: previous, key: _read.key),
      );
      _setNotice('无法读取设置', error: true);
    } finally {
      ticket.end();
    }
  }

  Future<void> setLanguage(UiLanguage language) async {
    if (data.language == language) return;
    await _runAction<UiLanguage>(
      slot: _language,
      current: () => _languageAction,
      set: _setLanguage,
      request: (ticket) => repository.savePreferences(
        language,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (saved) =>
          _replace(data.copyWith(language: saved), _SettingsPart.language),
      okNotice: (saved) => saved == UiLanguage.en ? 'Language saved' : '语言已保存',
      failNotice: '保存失败',
    );
  }

  void patchNotify(NotifyChannel channel, NotifyChannelSettings next) {
    if (isDisposed) return;
    _notifyDirty.add(channel);
    _notifyRevisions[channel] = (_notifyRevisions[channel] ?? 0) + 1;
    _replace(
      data.copyWith(notifications: data.notifications.replacing(channel, next)),
      _SettingsPart.notifications,
    );
  }

  Future<void> saveNotifications() {
    var submittedRevisions = <NotifyChannel, int>{};
    void captureSubmission() {
      submittedRevisions = Map<NotifyChannel, int>.of(_notifyRevisions);
    }

    return _runAction<NotificationSettings>(
      slot: _notify,
      current: () => _notifyAction,
      set: _setNotify,
      request: (ticket) {
        if (!_loadAttempted || _notificationsLoaded) {
          captureSubmission();
          return repository.saveNotifications(
            data.notifications,
            cancellation: ticket.cancellation,
          );
        }
        return _saveNotificationsAfterReload(ticket, captureSubmission);
      },
      onSuccess: (saved) {
        _notificationsLoaded = true;
        var confirmed = saved;
        for (final channel in NotifyChannel.values) {
          if ((_notifyRevisions[channel] ?? 0) !=
              (submittedRevisions[channel] ?? 0)) {
            confirmed = confirmed.replacing(
              channel,
              data.notifications.of(channel),
            );
          } else {
            _notifyDirty.remove(channel);
          }
        }
        _replace(
          data.copyWith(notifications: confirmed),
          _SettingsPart.notifications,
        );
      },
      okNotice: (_) => _notifyDirty.isEmpty ? '通知设置已保存' : '已保存提交的设置，仍有未保存的修改',
      failNotice: '保存失败',
    );
  }

  Future<void> testChannel(NotifyChannel channel) async {
    if (isDisposed || _testAction.status == ActionStatus.submitting) return;
    if (!channel.canTest) {
      _setNotice('此通道不支持连通测试', error: true);
      return;
    }
    _testingChannel = channel;
    await _runAction<void>(
      slot: _test,
      current: () => _testAction,
      set: _setTest,
      request: (ticket) => repository.testNotification(
        channel,
        data.notifications.of(channel),
        cancellation: ticket.cancellation,
      ),
      okNotice: (_) => '测试已发送',
      failNotice: '测试失败',
      always: (ticket) {
        if (ticket.isCurrent) _testingChannel = null;
      },
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (isDisposed || _passwordAction.status == ActionStatus.submitting) return;
    if (newPassword.length < minPasswordLength) {
      _setNotice('新密码至少 $minPasswordLength 位', error: true);
      return;
    }
    if (newPassword != confirmPassword) {
      _setNotice('两次密码不一致', error: true);
      return;
    }
    await _runAction<void>(
      slot: _password,
      current: () => _passwordAction,
      set: _setPassword,
      request: (ticket) => repository.changePassword(
        oldPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (_) => _passwordChanged = true,
      okNotice: (_) => '密码已改，请重新登录',
      failNotice: '改密失败',
    );
  }

  Future<void> saveSecurity({
    required AccessMode mode,
    required String allowedCidrsText,
    required bool trustProxyHeaders,
    required String trustedProxyCidrsText,
  }) {
    if (_loadAttempted && !_securityLoaded) {
      _setNotice('访问策略尚未读到，请先刷新后再保存', error: true);
      return Future<void>.value();
    }
    return _runAction<AccessPolicy>(
      slot: _security,
      current: () => _securityAction,
      set: _setSecurity,
      request: (ticket) => repository.saveSecurity(
        AccessPolicy(
          mode: mode,
          allowedCidrs: splitCidrLines(allowedCidrsText),
          trustProxyHeaders: trustProxyHeaders,
          trustedProxyCidrs: splitCidrLines(trustedProxyCidrsText),
          clientIp: data.security.clientIp,
          clientAllowed: data.security.clientAllowed,
        ),
        cancellation: ticket.cancellation,
      ),
      onSuccess: (saved) {
        _securityLoaded = true;
        _replace(data.copyWith(security: saved), _SettingsPart.security);
      },
      okNotice: (_) => '访问策略已保存',
      failNotice: '访问策略保存失败',
    );
  }

  Future<void> setHttps(bool enabled) => _runAction<HttpsSettings>(
    slot: _https,
    current: () => _httpsAction,
    set: _setHttps,
    request: (ticket) =>
        repository.saveHttps(enabled, cancellation: ticket.cancellation),
    onSuccess: (saved) =>
        _replace(data.copyWith(https: saved), _SettingsPart.https),
    okNotice: (_) =>
        enabled ? 'HTTPS 已开启，请用新地址重新登录' : 'HTTPS 已关闭，请用 HTTP 地址重新登录',
    failNotice: 'HTTPS 配置保存失败',
  );

  Future<void> uploadCertificate({
    required String certificate,
    required String privateKey,
  }) => _runAction<HttpsSettings>(
    slot: _httpsUpload,
    current: () => _httpsUploadAction,
    set: _setHttpsUploadAction,
    request: (ticket) => repository.uploadCustomCertificate(
      certificate: certificate,
      privateKey: privateKey,
      cancellation: ticket.cancellation,
    ),
    onSuccess: (saved) =>
        _replace(data.copyWith(https: saved), _SettingsPart.https),
    okNotice: (_) => '自定义证书已上传并生效',
    failNotice: '证书上传失败，请检查格式是否正确',
  );

  Future<void> deleteCertificate() => _runAction<HttpsSettings>(
    slot: _httpsDelete,
    current: () => _httpsDeleteAction,
    set: _setHttpsDeleteAction,
    request: (ticket) =>
        repository.deleteCustomCertificate(cancellation: ticket.cancellation),
    onSuccess: (saved) =>
        _replace(data.copyWith(https: saved), _SettingsPart.https),
    okNotice: (_) => '已删除自定义证书，已回退到自签名证书',
    failNotice: '证书删除失败',
  );

  Future<void> reissueCertificate() => _runAction<HttpsSettings>(
    slot: _httpsReissue,
    current: () => _httpsReissueAction,
    set: _setHttpsReissueAction,
    request: (ticket) =>
        repository.reissueCertificate(cancellation: ticket.cancellation),
    onSuccess: (saved) =>
        _replace(data.copyWith(https: saved), _SettingsPart.https),
    okNotice: (_) => '自签名证书已重新颁发，已覆盖当前主机',
    failNotice: '证书重新颁发失败',
  );

  Future<void> saveQuota({int? deviceLimit, int? smsHourlyLimit}) =>
      _runAction<DeveloperQuota>(
        slot: _quota,
        current: () => _quotaAction,
        set: _setQuota,
        request: (ticket) => repository.saveDeveloper(
          deviceLimit: deviceLimit,
          smsHourlyLimit: smsHourlyLimit,
          cancellation: ticket.cancellation,
        ),
        onSuccess: (saved) =>
            _replace(data.copyWith(quota: saved), _SettingsPart.quota),
        okNotice: (_) => deviceLimit != null ? '设备配额已保存' : '短信小时限额已保存',
        failNotice: '保存失败',
      );

  Future<void> setSmsAutoClear(bool enabled) async {
    if (isDisposed) return;
    await _runAction<SmsModemSettings>(
      slot: _smsModem,
      current: () => _smsModemAction,
      set: _setSmsModemAction,
      request: (ticket) => repository.saveSmsModemSettings(
        enabled,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (next) =>
          _replace(data.copyWith(smsModem: next), _SettingsPart.smsModem),
      okNotice: (_) => enabled ? '已开启自动清理模组短信存储' : '已关闭自动清理；邮箱满了可能挡新短信',
      failNotice: '短信存储设置保存失败',
    );
  }

  Future<void> setVowifiMtu(bool enabled) async {
    if (isDisposed) return;
    await _runAction<VowifiMtuSettings>(
      slot: _vowifiMtu,
      current: () => _vowifiMtuAction,
      set: _setVowifiMtuAction,
      request: (ticket) => repository.saveVowifiSettings(
        enabled,
        cancellation: ticket.cancellation,
      ),
      onSuccess: (next) =>
          _replace(data.copyWith(vowifiMtu: next), _SettingsPart.vowifiMtu),
      okNotice: (_) => '设置已保存，请重连 VoWiFi 后生效',
      failNotice: 'VoWiFi 兼容设置保存失败',
    );
  }

  Future<void> activateLicense(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      _setNotice('先填授权码', error: true);
      return;
    }
    await _runAction<ProductLicense>(
      slot: _license,
      current: () => _licenseAction,
      set: _setLicenseAction,
      request: (_) => licenseStore.activate(trimmed),
      onSuccess: (next) =>
          _replace(data.copyWith(license: next), _SettingsPart.license),
      okNotice: (_) => '授权码已绑定本机',
      failNotice: '授权绑定失败',
    );
  }

  Future<void> deactivateLicense() async {
    if (!data.license.isActive) {
      _setNotice('当前未激活', error: true);
      return;
    }
    await _runAction<ProductLicense>(
      slot: _license,
      current: () => _licenseAction,
      set: _setLicenseAction,
      request: (_) => licenseStore.deactivate(),
      onSuccess: (next) =>
          _replace(data.copyWith(license: next), _SettingsPart.license),
      okNotice: (_) => '已解除本机激活',
      failNotice: '解除激活失败',
    );
  }

  Future<void> _runAction<T>({
    required RequestSlot slot,
    required ActionState Function() current,
    required void Function(ActionState next) set,
    required Future<T> Function(RequestTicket ticket) request,
    required String Function(T result) okNotice,
    required String failNotice,
    void Function(T result)? onSuccess,
    void Function(T result)? afterNotice,
    void Function(RequestTicket ticket)? always,
  }) => runAction<T>(
    slot: slot,
    current: current,
    set: set,
    request: request,
    onSuccess: (result, _) {
      onSuccess?.call(result);
      set(const ActionState.succeeded());
      _setNotice(okNotice(result));
      afterNotice?.call(result);
      return null;
    },
    onFailure: (error) => _setNotice(
      error is LicenseActivateException ? error.message : failNotice,
      error: true,
    ),
    always: always,
  );

  Future<NotificationSettings> _saveNotificationsAfterReload(
    RequestTicket ticket,
    void Function() captureSubmission,
  ) async {
    final remote = await repository.fetchNotifications(
      cancellation: ticket.cancellation,
    );
    if (!ticket.isCurrent) {
      return remote;
    }
    var merged = remote;
    for (final channel in _notifyDirty) {
      merged = merged.replacing(channel, data.notifications.of(channel));
    }
    captureSubmission();
    return repository.saveNotifications(
      merged,
      cancellation: ticket.cancellation,
    );
  }

  Future<({_SettingsPart part, Object? value, Object? error})> _capture(
    _SettingsPart part,
    Future<Object?> future,
  ) async {
    try {
      return (part: part, value: await future, error: null);
    } catch (error) {
      return (part: part, value: null, error: error);
    }
  }

  Future<T?> _ignore<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  void _replace(SettingsSnapshot next, _SettingsPart part) {
    if (isDisposed) return;
    _partRevisions[part] = (_partRevisions[part] ?? 0) + 1;
    _setSnapshot(QueryState<SettingsSnapshot>.data(data: next, key: _read.key));
  }

  bool _changedSince(_SettingsPart part, Map<_SettingsPart, int> revisions) =>
      (_partRevisions[part] ?? 0) != (revisions[part] ?? 0);

  // A slow read may still fill unrelated sections, but cannot undo a newer
  // edit/save. Compare generations, not values (A -> B -> A is still an edit).
  SettingsSnapshot _mergeLoaded(
    SettingsSnapshot loaded,
    Map<_SettingsPart, int> revisions,
  ) {
    final current = data;
    bool changed(_SettingsPart part) => _changedSince(part, revisions);
    return SettingsSnapshot(
      language: changed(_SettingsPart.language)
          ? current.language
          : loaded.language,
      info: changed(_SettingsPart.info) ? current.info : loaded.info,
      notifications: changed(_SettingsPart.notifications)
          ? current.notifications
          : loaded.notifications,
      security: changed(_SettingsPart.security)
          ? current.security
          : loaded.security,
      https: changed(_SettingsPart.https) ? current.https : loaded.https,
      quota: changed(_SettingsPart.quota) ? current.quota : loaded.quota,
      license: changed(_SettingsPart.license)
          ? current.license
          : loaded.license,
      smsModem: changed(_SettingsPart.smsModem)
          ? current.smsModem
          : loaded.smsModem,
      vowifiMtu: changed(_SettingsPart.vowifiMtu)
          ? current.vowifiMtu
          : loaded.vowifiMtu,
      gatewayLicense: loaded.gatewayLicense,
    );
  }

  void _setSnapshot(QueryState<SettingsSnapshot> next) =>
      publish(() => _snapshot = next);

  void _setLanguage(ActionState next) => publish(() => _languageAction = next);

  void _setNotify(ActionState next) => publish(() => _notifyAction = next);

  void _setTest(ActionState next) => publish(() => _testAction = next);

  void _setPassword(ActionState next) => publish(() => _passwordAction = next);

  void _setSecurity(ActionState next) => publish(() => _securityAction = next);

  void _setHttps(ActionState next) => publish(() => _httpsAction = next);

  void _setHttpsUploadAction(ActionState next) =>
      publish(() => _httpsUploadAction = next);

  void _setHttpsDeleteAction(ActionState next) =>
      publish(() => _httpsDeleteAction = next);

  void _setHttpsReissueAction(ActionState next) =>
      publish(() => _httpsReissueAction = next);

  void _setQuota(ActionState next) => publish(() => _quotaAction = next);

  void _setLicenseAction(ActionState next) =>
      publish(() => _licenseAction = next);

  void _setSmsModemAction(ActionState next) =>
      publish(() => _smsModemAction = next);

  void _setVowifiMtuAction(ActionState next) =>
      publish(() => _vowifiMtuAction = next);

  void _setNotice(String text, {bool error = false}) => publish(() {
    _notice = text;
    _noticeError = error;
    _noticeSeq += 1;
  });
}

enum _SettingsPart {
  language('界面语言'),
  info('系统信息'),
  notifications('通知设置'),
  security('访问策略'),
  https('HTTPS'),
  quota('开发配额'),
  license('本机授权'),
  gatewayLicense('网关授权'),
  smsModem('短信存储'),
  vowifiMtu('VoWiFi 兼容');

  const _SettingsPart(this.label);

  /// 报给用户的节名，必须对得上设置页上真实存在的卡片。
  final String label;
}
