import pathlib, re
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')

def read(rel):
    return (root/rel).read_text(encoding='utf-8')

def write(rel, text):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8', newline='\n')
    print('WROTE', rel)

# --- SettingsApi: SMS + GET license ---
api = read('lib/features/settings/data/settings_api.dart')
if 'fetchSmsModemSettings' not in api:
    methods = '''
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/settings/sms',
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return SmsModemSettings(
      autoClearModemStorage: map['auto_clear_modem_storage'] != false,
    );
  }

  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'PUT',
      routeTemplate: '/api/settings/sms',
      body: <String, Object?>{
        'auto_clear_modem_storage': autoClearModemStorage,
      },
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return SmsModemSettings(
      autoClearModemStorage: map['auto_clear_modem_storage'] != false,
    );
  }

  /// Router/gateway seat only. Do not POST/DELETE for android seat.
  Future<GatewayLicenseStatus> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) async {
    final data = await _transport.sendJson(
      method: 'GET',
      routeTemplate: '/api/license',
      cancellation: cancellation,
    );
    final map = _shape.map(data);
    return GatewayLicenseStatus(
      activated: map['activated'] == true,
      code: _shape.optionalString(map['code']),
      edition: _shape.optionalString(map['edition']),
      clientKind: _shape.optionalString(map['client_kind']),
    );
  }
'''
    # insert before closing brace of class
    api = api.rstrip()
    if api.endswith('}'):
        api = api[:-1] + methods + '}\n'
    write('lib/features/settings/data/settings_api.dart', api)

# --- SettingsRepository ---
repo = read('lib/features/settings/data/settings_repository.dart')
if 'fetchSmsModemSettings' not in repo:
    iface = '''
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  });

  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  });

  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  });
'''
    repo = repo.replace(
        '  Future<DeveloperQuota> saveDeveloper({',
        iface + '\n  Future<DeveloperQuota> saveDeveloper({',
        1,
    )
    impl = '''
  @override
  Future<SmsModemSettings> fetchSmsModemSettings({
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.fetchSmsModemSettings(cancellation: cancellation),
    );
  }

  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) {
    return guardShape(
      'local-settings-response',
      () => _api.saveSmsModemSettings(
        autoClearModemStorage,
        cancellation: cancellation,
      ),
    );
  }

  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({
    RequestCancellation? cancellation,
  }) {
    return _optionalDeveloper(
      () => _api.fetchGatewayLicense(cancellation: cancellation),
    );
  }
'''
    # before _optionalDeveloper
    repo = repo.replace(
        '  Future<T?> _optionalDeveloper<T>(Future<T> Function() body) async {',
        impl + '\n  Future<T?> _optionalDeveloper<T>(Future<T> Function() body) async {',
    )
    write('lib/features/settings/data/settings_repository.dart', repo)

print('api/repo ok')
