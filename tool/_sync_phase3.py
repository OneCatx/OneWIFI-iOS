import pathlib
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')
path = root/'lib/features/settings/state/settings_controller.dart'
t = path.read_text(encoding='utf-8')

if '_smsModem' not in t:
    t = t.replace(
        "       _license = RequestSlot(requestRegistry, 'settings.license');",
        "       _license = RequestSlot(requestRegistry, 'settings.license'),\n"
        "       _smsModem = RequestSlot(requestRegistry, 'settings.sms');",
    )
    t = t.replace(
        '  final RequestSlot _license;\n',
        '  final RequestSlot _license;\n  final RequestSlot _smsModem;\n',
    )
    t = t.replace(
        '  ActionState _licenseAction = const ActionState.idle();\n',
        '  ActionState _licenseAction = const ActionState.idle();\n'
        '  ActionState _smsModemAction = const ActionState.idle();\n',
    )
    t = t.replace(
        '  ActionState get licenseAction => _licenseAction;\n',
        '  ActionState get licenseAction => _licenseAction;\n'
        '  ActionState get smsModemAction => _smsModemAction;\n',
    )
    t = t.replace(
        '    _license,\n  ];',
        '    _license,\n    _smsModem,\n  ];',
    )
    # extend Future.wait
    t = t.replace(
        '        _capture(licenseStore.read()),\n      ]);',
        '        _capture(licenseStore.read()),\n'
        '        _capture(\n'
        '          repository.fetchSmsModemSettings(cancellation: ticket.cancellation),\n'
        '        ),\n'
        '        _capture(\n'
        '          repository.fetchGatewayLicense(cancellation: ticket.cancellation),\n'
        '        ),\n'
        '      ]);',
    )
    t = t.replace(
        '        license: results[4].value as ProductLicense?,\n      );',
        '        license: results[4].value as ProductLicense?,\n'
        '        smsModem: results[5].value as SmsModemSettings?,\n'
        '        gatewayLicense: results[6].value as GatewayLicenseStatus?,\n'
        '        clearGatewayLicense: results[6].value == null && results[6].error == null,\n'
        '      );',
    )

# add setSmsAutoClear before activateLicense
if 'setSmsAutoClear' not in t:
    method = '''
  Future<void> setSmsAutoClear(bool enabled) async {
    if (isDisposed) return;
    await _runAction<SmsModemSettings>(
      slot: _smsModem,
      current: () => _smsModemAction,
      set: _setSmsModemAction,
      request: (_) => repository.saveSmsModemSettings(enabled),
      onSuccess: (next) => _replace(data.copyWith(smsModem: next)),
      okNotice: (_) => enabled ? '已开启自动清理模组短信存储' : '已关闭自动清理；邮箱满了可能挡新短信',
      failNotice: '短信存储设置保存失败',
    );
  }

'''
    t = t.replace('  Future<void> activateLicense(String key) async {', method + '  Future<void> activateLicense(String key) async {')

if '_setSmsModemAction' not in t:
    t = t.replace(
        '  void _setLicenseAction(ActionState next) =>\n      publish(() => _licenseAction = next);',
        '  void _setLicenseAction(ActionState next) =>\n      publish(() => _licenseAction = next);\n\n'
        '  void _setSmsModemAction(ActionState next) =>\n      publish(() => _smsModemAction = next);',
    )

path.write_text(t, encoding='utf-8', newline='\n')
print('controller patched', 'setSmsAutoClear' in t, '_smsModem' in t)
