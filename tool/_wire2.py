import pathlib
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")

app = (root/"lib/app/app.dart").read_text(encoding="utf-8")
if "callsControllerFactory" not in app:
    app = app.replace(
        "    _smsFactory = _dependencies.createSmsController;\n",
        "    _smsFactory = _dependencies.createSmsController;\n"
        "    _callsFactory = _dependencies.createCallsController;\n",
    )
    # field declarations - find _smsFactory
    app = app.replace(
        "  late final SmsController Function() _smsFactory;\n",
        "  late final SmsController Function() _smsFactory;\n"
        "  late final CallsController Function() _callsFactory;\n",
    )
    # if typed differently
    if "late final CallsController Function() _callsFactory" not in app:
        # try without late final pattern
        import re
        m = re.search(r".*_smsFactory;.*\n", app)
        print("smsFactory line:", m.group(0) if m else None)
    app = app.replace(
        "            smsControllerFactory: _smsFactory,\n",
        "            smsControllerFactory: _smsFactory,\n"
        "            callsControllerFactory: _callsFactory,\n",
    )
    # import CallsController if needed
    if "calls/state/calls_controller.dart" not in app:
        app = app.replace(
            "import '../features/sms/state/sms_controller.dart';\n",
            "import '../features/sms/state/sms_controller.dart';\n"
            "import '../features/calls/state/calls_controller.dart';\n",
        )
    (root/"lib/app/app.dart").write_text(app, encoding="utf-8", newline="\n")
    print("app patched", "callsControllerFactory" in app, "_callsFactory" in app)
else:
    print("app already has calls")

# ensure shell StatefulWidget has callsController in constructor
shell = (root/"lib/app/android_oneims_shell.dart").read_text(encoding="utf-8")
# print ctor area
idx = shell.find("const AndroidOneImsShell")
print(shell[idx:idx+800])
