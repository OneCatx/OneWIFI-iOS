import 'package:flutter/material.dart';

import '../../../app/certificate_trust_dialog.dart';
import '../../../core/config/base_url_policy.dart';
import '../../../core/state/session_state.dart';
import '../../../core/state/state_failure.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/glass_backdrop.dart';
import '../../settings/data/product_license_store.dart';
import '../../settings/domain/gateway_settings.dart';
import '../../settings/domain/license_code.dart';
import '../state/session_controller.dart';
import 'widgets/login_form.dart';

final class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.controller,
    this.readLicense,
    this.bindLicense,
    super.key,
  });

  static const Key rootKey = Key('login-screen');
  static const Key hostFieldKey = Key('login-host');
  static const Key portFieldKey = Key('login-port');
  static const Key httpsSwitchKey = Key('login-https');
  static const Key usernameFieldKey = Key('login-username');
  static const Key passwordFieldKey = Key('login-password');
  static const Key licenseFieldKey = Key('login-license');
  static const Key signInTargetKey = Key('login-sign-in-target');
  static const Key retryTargetKey = Key('login-retry-target');
  static const Key fingerprintKey = Key('login-fingerprint');

  static const LoginFormKeys formKeys = (
    host: hostFieldKey,
    port: portFieldKey,
    https: httpsSwitchKey,
    username: usernameFieldKey,
    password: passwordFieldKey,
    signIn: signInTargetKey,
    retry: retryTargetKey,
    license: licenseFieldKey,
  );

  final SessionController controller;
  final Future<ProductLicense> Function()? readLicense;
  final Future<ProductLicense> Function(String code)? bindLicense;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

final class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _license = TextEditingController();
  final _hostFocus = FocusNode();
  final _portFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _licenseFocus = FocusNode();
  late bool _https;
  String? _originError;
  String? _licenseNotice;
  bool _licensed = true;
  bool _binding = false;

  Future<ProductLicense> _readLicense() =>
      (widget.readLicense ?? createProductLicenseStore().read)();

  Future<ProductLicense> _bindLicense(String code) =>
      (widget.bindLicense ?? createProductLicenseStore().activate)(code);

  @override
  void initState() {
    super.initState();
    final parts = BaseUrlPolicy.split(widget.controller.origin);
    _host = TextEditingController(text: parts.host);
    _port = TextEditingController(text: parts.port);
    _https = parts.https;
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    try {
      final state = await _readLicense();
      if (!mounted) return;
      setState(() => _licensed = state.isActive);
    } catch (error) {
      if (!mounted) return;
      // 测试 / 无原生通道时不挡登录；真机读库失败则露出授权码。
      setState(() => _licensed = error.toString().contains('没有激活通道'));
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _license.dispose();
    _hostFocus.dispose();
    _portFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _licenseFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final session = widget.controller.state;
        final busy = session.status == SessionStatus.signingIn || _binding;
        final notice =
            _licenseNotice ??
            switch (session.status) {
              SessionStatus.expired => '登录已过期，请重新登录',
              SessionStatus.failed => session.failure?.message ?? '登录失败。',
              _ => null,
            };
        return Scaffold(
          key: LoginScreen.rootKey,
          backgroundColor: Colors.transparent,
          body: GlassBackdrop(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: OneInsets.page,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - OneSpacing.large,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: LoginForm(
                          formKey: _formKey,
                          host: _host,
                          port: _port,
                          username: _username,
                          password: _password,
                          hostFocus: _hostFocus,
                          portFocus: _portFocus,
                          usernameFocus: _usernameFocus,
                          passwordFocus: _passwordFocus,
                          https: _https,
                          busy: busy,
                          notice: notice,
                          originError: _originError,
                          showRetry: session.status == SessionStatus.failed,
                          portValidator: _portError,
                          onChanged: () => setState(() {}),
                          onHttpsChanged: _setHttps,
                          onSubmit: _submit,
                          onRetry: widget.controller.bootstrap,
                          keys: LoginScreen.formKeys,
                          license: _license,
                          licenseFocus: _licenseFocus,
                          showLicense: !_licensed,
                          licenseError: LicenseCode.localError(_license.text),
                          onCertificate: widget.controller.connections == null
                              ? null
                              : _configureCertificate,
                          certificateKey: LoginScreen.fingerprintKey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _setHttps(bool value) {
    setState(() {
      _https = value;
      _originError = null;
    });
  }

  Future<void> _configureCertificate() async {
    final connections = widget.controller.connections;
    if (connections == null) return;
    try {
      final origin = BaseUrlPolicy.fromHostAndPort(
        host: _host.text,
        port: _port.text,
        https: true,
      );
      await showCertificateTrustDialog(
        context: context,
        connections: connections,
        origin: origin,
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _originError = error.message);
    }
  }

  String? _portError(String? value) {
    final port = value?.trim() ?? '';
    if (port.isEmpty) {
      return '请输入端口。';
    }
    final parsed = int.tryParse(port);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      return '端口范围 1–65535。';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _originError = null;
      _licenseNotice = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_host.text.trim().isEmpty) {
        _hostFocus.requestFocus();
      } else if (_portError(_port.text) != null) {
        _portFocus.requestFocus();
      } else if (_username.text.trim().isEmpty) {
        _usernameFocus.requestFocus();
      } else if (!_licensed && _license.text.trim().isEmpty) {
        _licenseFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
      return;
    }
    if (!_licensed) {
      final local = LicenseCode.validate(_license.text);
      if (!local.ok) {
        setState(() => _licenseNotice = '请输入激活码，格式 XXXX-XXXX-XXXX-XXXX');
        _licenseFocus.requestFocus();
        return;
      }
    }
    final Uri origin;
    try {
      origin = BaseUrlPolicy.fromHostAndPort(
        host: _host.text,
        port: _port.text,
        https: _https,
      );
    } on FormatException catch (error) {
      setState(() => _originError = error.message);
      _hostFocus.requestFocus();
      return;
    }
    _commit(origin);
  }

  Future<void> _commit(Uri origin, {bool allowHttpsUpgrade = true}) async {
    if (origin != widget.controller.origin) {
      await widget.controller.changeOrigin(origin);
      if (!mounted) return;
    }
    if (!_licensed) {
      final local = LicenseCode.validate(_license.text);
      setState(() => _binding = true);
      try {
        final next = await _bindLicense(local.normalized);
        if (!mounted) return;
        if (!next.isActive) {
          setState(() {
            _binding = false;
            _licenseNotice = '激活失败';
          });
          return;
        }
        setState(() {
          _binding = false;
          _licensed = true;
        });
      } on LicenseActivateException catch (error) {
        if (!mounted) return;
        setState(() {
          _binding = false;
          _licenseNotice = error.message;
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _binding = false;
          _licenseNotice = '激活失败';
        });
        return;
      }
    }
    await widget.controller.signIn(_username.text, _password.text);
    if (!mounted) return;
    if (!allowHttpsUpgrade || origin.scheme == 'https') return;
    if (widget.controller.state.status == SessionStatus.signedIn) return;
    if (!_shouldRetryHttps(widget.controller.state.failure)) return;
    setState(() => _https = true);
    final upgraded = BaseUrlPolicy.fromHostAndPort(
      host: _host.text,
      port: _port.text,
      https: true,
    );
    await _commit(upgraded, allowHttpsUpgrade: false);
  }

  bool _shouldRetryHttps(StateFailure? failure) {
    if (failure == null) return false;
    final code = failure.backendCode;
    if (code == 'https_required' || code == 'invalid_redirect_host') {
      return true;
    }
    final status = failure.statusCode;
    return failure.kind == StateFailureKind.protocol &&
        status != null &&
        status >= 300 &&
        status < 400;
  }
}
