import pathlib
root = pathlib.Path(r'E:\GQ\Ultra\ONEWIFI\android')

def read(rel):
    return (root/rel).read_text(encoding='utf-8')

def write(rel, text):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8', newline='\n')
    print('WROTE', rel, len(text.encode('utf-8')))

# 1) error codes
err = read('lib/core/http/backend_error_codes.dart')
for code in ["invalid_dial_number", "call_not_found", "call_state", "vowifi_runtime_unavailable"]:
    needle = f"    '{code}',\n"
    if f"'{code}'" not in err:
        anchor = "    'invalid_call_id',\n"
        if anchor in err:
            err = err.replace(anchor, anchor + needle)
        else:
            err = err.replace("    'voice_calls_removed',\n", needle + "    'voice_calls_removed',\n")
write('lib/core/http/backend_error_codes.dart', err)

# 2) domain
gs = read('lib/features/settings/domain/gateway_settings.dart')
if 'SmsModemSettings' not in gs:
    insert = '''
final class SmsModemSettings {
  const SmsModemSettings({this.autoClearModemStorage = true});

  final bool autoClearModemStorage;
}

/// Gateway/router seat from GET /api/license. Android seat stays native.
final class GatewayLicenseStatus {
  const GatewayLicenseStatus({
    this.activated = false,
    this.code = '',
    this.edition = '',
    this.clientKind = '',
  });

  final bool activated;
  final String code;
  final String edition;
  final String clientKind;
}

'''
    gs = gs.replace('final class ProductLicense {', insert + 'final class ProductLicense {')

if 'smsModem' not in gs:
    gs = gs.replace(
        '    this.license = const ProductLicense(),\n    this.update,\n  });',
        '    this.license = const ProductLicense(),\n    this.gatewayLicense,\n    this.smsModem = const SmsModemSettings(),\n    this.update,\n  });',
    )
    gs = gs.replace(
        '  final ProductLicense license;\n  final GatewayUpdate? update;',
        '  final ProductLicense license;\n  final GatewayLicenseStatus? gatewayLicense;\n  final SmsModemSettings smsModem;\n  final GatewayUpdate? update;',
    )
    gs = gs.replace(
        '    ProductLicense? license,\n    GatewayUpdate? update,\n    bool clearHttps = false,\n    bool clearQuota = false,\n    bool clearUpdate = false,\n  }) {',
        '    ProductLicense? license,\n    GatewayLicenseStatus? gatewayLicense,\n    SmsModemSettings? smsModem,\n    GatewayUpdate? update,\n    bool clearHttps = false,\n    bool clearQuota = false,\n    bool clearGatewayLicense = false,\n    bool clearUpdate = false,\n  }) {',
    )
    gs = gs.replace(
        '      license: license ?? this.license,\n      update: clearUpdate ? null : (update ?? this.update),\n    );',
        '      license: license ?? this.license,\n      gatewayLicense: clearGatewayLicense\n          ? null\n          : (gatewayLicense ?? this.gatewayLicense),\n      smsModem: smsModem ?? this.smsModem,\n      update: clearUpdate ? null : (update ?? this.update),\n    );',
    )
write('lib/features/settings/domain/gateway_settings.dart', gs)
print('phase1 ok')
