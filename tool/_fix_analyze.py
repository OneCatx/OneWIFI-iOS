import pathlib, re
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")

# 1) OneStatusTone.danger -> critical
p = root/"lib/features/calls/presentation/calls_screen.dart"
t = p.read_text(encoding="utf-8")
t = t.replace("OneStatusTone.danger", "OneStatusTone.critical")
p.write_text(t, encoding="utf-8", newline="\n")
print("tone fixed")

# 2) add _setSmsModemAction
sc_path = root/"lib/features/settings/state/settings_controller.dart"
sc = sc_path.read_text(encoding="utf-8")
if "void _setSmsModemAction" not in sc:
    sc = sc.replace(
        "  void _setLicenseAction(ActionState next) =>\n      publish(() => _licenseAction = next);",
        "  void _setLicenseAction(ActionState next) =>\n      publish(() => _licenseAction = next);\n\n"
        "  void _setSmsModemAction(ActionState next) =>\n      publish(() => _smsModemAction = next);",
    )
    if "void _setSmsModemAction" not in sc:
        # try single line
        sc = sc.replace(
            "  void _setLicenseAction(ActionState next) => publish(() => _licenseAction = next);",
            "  void _setLicenseAction(ActionState next) => publish(() => _licenseAction = next);\n\n"
            "  void _setSmsModemAction(ActionState next) => publish(() => _smsModemAction = next);",
        )
    sc_path.write_text(sc, encoding="utf-8", newline="\n")
print("setter", "void _setSmsModemAction" in sc_path.read_text(encoding="utf-8"))

# 3) Fake SettingsRepository stubs in tests - find class FakeSettingsRepository or similar
for test in root.glob("test/**/*.dart"):
    text = test.read_text(encoding="utf-8")
    if "implements SettingsRepository" not in text:
        continue
    if "fetchSmsModemSettings" in text:
        continue
    # insert methods before last closing of that class - find implements SettingsRepository
    stub = '''
  @override
  Future<SmsModemSettings> fetchSmsModemSettings({RequestCancellation? cancellation}) async =>
      const SmsModemSettings();

  @override
  Future<SmsModemSettings> saveSmsModemSettings(
    bool autoClearModemStorage, {
    RequestCancellation? cancellation,
  }) async =>
      SmsModemSettings(autoClearModemStorage: autoClearModemStorage);

  @override
  Future<GatewayLicenseStatus?> fetchGatewayLicense({RequestCancellation? cancellation}) async =>
      null;
'''
    # ensure imports - gateway_settings usually already imported via settings
    # insert before saveDeveloper or at end of class before matching - simpler: after fetchDeveloper if present
    if "Future<DeveloperQuota?> fetchDeveloper" in text:
        # find the method end is hard; insert right after "implements SettingsRepository {" line's class - after first method
        text2 = text.replace(
            "implements SettingsRepository {",
            "implements SettingsRepository {" + stub,
            1,
        )
        # add import if needed
        if "gateway_settings.dart" not in text2 and "SmsModemSettings" in stub:
            # most tests already import domain
            pass
        test.write_text(text2, encoding="utf-8", newline="\n")
        print("stubbed", test.relative_to(root))
    else:
        text2 = text.replace(
            "implements SettingsRepository {",
            "implements SettingsRepository {" + stub,
            1,
        )
        test.write_text(text2, encoding="utf-8", newline="\n")
        print("stubbed-alt", test.relative_to(root))

# 4) session_gate_test
sgt = root/"test/app/session_gate_test.dart"
if sgt.exists():
    t = sgt.read_text(encoding="utf-8")
    if "callsControllerFactory" not in t:
        t = t.replace(
            "smsControllerFactory:",
            "callsControllerFactory: () => throw UnimplementedError('calls'),\n      smsControllerFactory:",
        )
        # might need better fake - search SessionGate(
        sgt.write_text(t, encoding="utf-8", newline="\n")
        print("session_gate_test patched", t.count("callsControllerFactory"))
