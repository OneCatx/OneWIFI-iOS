import pathlib
root = pathlib.Path(r"E:\GQ\Ultra\ONEWIFI\android")

def rw(rel, fn):
    p = root/rel
    t = p.read_text(encoding="utf-8")
    n = fn(t)
    if n != t:
        p.write_text(n, encoding="utf-8", newline="\n")
        print("patched", rel)
    else:
        print("noop", rel)

# fix calls_controller notice
def fix_cc(t):
    t = t.replace(
        "final failure = _calls.failure;\n      _setNotice(failure?.message ?? '无法拉取通话列表', error: true);",
        "final failure = _calls.failure;\n      final code = failure?.backendCode;\n      _setNotice(code == null || code.isEmpty ? '无法拉取通话列表' : '无法拉取通话列表（$code）', error: true);",
    )
    return t
rw("lib/features/calls/state/calls_controller.dart", fix_cc)

def fix_api(t):
    return t.replace("import 'dart:convert';\n", "")
rw("lib/features/calls/data/calls_api.dart", fix_api)

# wire app_dependencies
def fix_ad(t):
    if "CallsApi" in t:
        return t
    t = t.replace(
        "import '../features/automation/state/automation_controller.dart';\n",
        "import '../features/automation/state/automation_controller.dart';\n"
        "import '../features/calls/data/calls_api.dart';\n"
        "import '../features/calls/data/calls_repository.dart';\n"
        "import '../features/calls/state/calls_controller.dart';\n",
    )
    t = t.replace(
        "      DefaultSmsRepository(SmsApi(transport)),\n",
        "      DefaultSmsRepository(SmsApi(transport)),\n"
        "      DefaultCallsRepository(CallsApi(transport)),\n"
        "      origins.read,\n"
        "      tokens.read,\n",
    )
    t = t.replace(
        "    this._smsRepository,\n    this._proxyRepository,\n",
        "    this._smsRepository,\n    this._callsRepository,\n"
        "    this._originProvider,\n    this._tokenProvider,\n"
        "    this._proxyRepository,\n",
    )
    t = t.replace(
        "  final SmsRepository _smsRepository;\n  final ProxyRepository _proxyRepository;\n",
        "  final SmsRepository _smsRepository;\n  final CallsRepository _callsRepository;\n"
        "  final Future<Uri> Function() _originProvider;\n"
        "  final Future<String?> Function(Uri origin) _tokenProvider;\n"
        "  final ProxyRepository _proxyRepository;\n",
    )
    # factory createCallsController after createSmsController
    marker = "  SmsController createSmsController() {"
    idx = t.find(marker)
    if idx < 0:
        raise SystemExit("sms factory missing")
    # find end of createSmsController method
    end = t.find("  ProxyController createProxyController()", idx)
    insert = '''  CallsController createCallsController() {
    if (_disposed) throw StateError('App dependencies are disposed.');
    return CallsController(
      repository: _callsRepository,
      originProvider: _originProvider,
      tokenProvider: _tokenProvider,
      requestRegistry: _requestRegistry,
    );
  }

'''
    t = t[:end] + insert + t[end:]
    return t
rw("lib/app/app_dependencies.dart", fix_ad)

# session_gate
def fix_sg(t):
    if "CallsController" in t:
        return t
    t = t.replace(
        "import '../features/sms/state/sms_controller.dart';\n",
        "import '../features/sms/state/sms_controller.dart';\n"
        "import '../features/calls/state/calls_controller.dart';\n",
    )
    t = t.replace(
        "    required this.smsControllerFactory,\n",
        "    required this.smsControllerFactory,\n"
        "    required this.callsControllerFactory,\n",
    )
    t = t.replace(
        "  final SmsController Function() smsControllerFactory;\n",
        "  final SmsController Function() smsControllerFactory;\n"
        "  final CallsController Function() callsControllerFactory;\n",
    )
    t = t.replace(
        "  SmsController? _smsController;\n",
        "  SmsController? _smsController;\n  CallsController? _callsController;\n",
    )
    t = t.replace(
        "        smsController: _smsController!,\n",
        "        smsController: _smsController!,\n"
        "        callsController: _callsController!,\n",
    )
    t = t.replace(
        """        !identical(
          oldWidget.smsControllerFactory,
          widget.smsControllerFactory,
        ) ||""",
        """        !identical(
          oldWidget.smsControllerFactory,
          widget.smsControllerFactory,
        ) ||
        !identical(
          oldWidget.callsControllerFactory,
          widget.callsControllerFactory,
        ) ||""",
    )
    t = t.replace(
        """    if (signedIn && _smsController == null) {
      _smsController = widget.smsControllerFactory();
      _smsController?.startOtpWatch();
    }""",
        """    if (signedIn && _smsController == null) {
      _smsController = widget.smsControllerFactory();
      _smsController?.startOtpWatch();
    }
    if (signedIn && _callsController == null) {
      _callsController = widget.callsControllerFactory();
    }""",
    )
    t = t.replace(
        "    _smsController?.dispose();\n    _smsController = null;\n",
        "    _smsController?.dispose();\n    _smsController = null;\n"
        "    _callsController?.dispose();\n    _callsController = null;\n",
    )
    return t
rw("lib/app/session_gate.dart", fix_sg)

# shell
def fix_shell(t):
    t = t.replace(
        "import '../features/calls/presentation/calls_placeholder_screen.dart';\n",
        "import '../features/calls/presentation/calls_screen.dart';\n"
        "import '../features/calls/state/calls_controller.dart';\n",
    )
    if "required this.callsController" not in t:
        t = t.replace(
            "    required this.smsController,\n",
            "    required this.smsController,\n    required this.callsController,\n",
        )
        t = t.replace(
            "  final SmsController smsController;\n",
            "  final SmsController smsController;\n  final CallsController callsController;\n",
        )
    t = t.replace(
        "        return const CallsPlaceholderScreen();",
        "        return CallsScreen(calls: widget.callsController, devices: widget.deviceListController);",
    )
    return t
rw("lib/app/android_oneims_shell.dart", fix_shell)

# app.dart SessionGate construction
def fix_app(t):
    if "callsControllerFactory" in t:
        return t
    t = t.replace(
        "              smsControllerFactory: deps.createSmsController,\n",
        "              smsControllerFactory: deps.createSmsController,\n"
        "              callsControllerFactory: deps.createCallsController,\n",
    )
    return t
rw("lib/app/app.dart", fix_app)

print("done wire")
