import 'dart:async';

import 'package:flutter/material.dart';

import '../core/state/session_state.dart';
import '../design/tokens/one_tokens.dart';
import '../design/widgets/one_status_hero.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/state/session_controller.dart';
import '../features/automation/state/automation_controller.dart';
import '../features/calls/state/calls_controller.dart';
import '../features/certificates/state/certificate_controller.dart';
import '../features/devices/state/device_detail_controller.dart';
import '../features/devices/state/device_list_controller.dart';
import '../features/esim/state/esim_controller.dart';
import '../features/export_proxy/state/export_proxy_controller.dart';
import '../features/extensions/state/extensions_controller.dart';
import '../features/logs/state/logs_controller.dart';
import '../features/overview/state/overview_controller.dart';
import '../features/proxy/state/mihomo_connection_controller.dart';
import '../features/proxy/state/proxy_controller.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/sms/state/sms_controller.dart';
import '../features/upstream/state/upstream_controller.dart';
import 'android_oneims_shell.dart';
import 'appearance_controller.dart';

final class SessionGate extends StatefulWidget {
  const SessionGate({
    required this.sessionController,
    required this.overviewControllerFactory,
    required this.deviceListControllerFactory,
    required this.deviceDetailControllerFactory,
    required this.esimControllerFactory,
    required this.smsControllerFactory,
    required this.callsControllerFactory,
    required this.proxyControllerFactory,
    this.mihomoConnectionControllerFactory,
    this.logsControllerFactory,
    this.automationControllerFactory,
    this.extensionsControllerFactory,
    this.upstreamControllerFactory,
    this.exportProxyControllerFactory,
    this.settingsControllerFactory,
    this.certificateControllerFactory,
    required this.appearance,
    super.key,
  });

  static const Key bootingKey = Key('session-booting');

  final SessionController sessionController;
  final OverviewController Function() overviewControllerFactory;
  final DeviceListController Function() deviceListControllerFactory;
  final DeviceDetailController Function(String deviceId)
  deviceDetailControllerFactory;
  final EsimController Function(String deviceId) esimControllerFactory;
  final SmsController Function() smsControllerFactory;
  final CallsController Function() callsControllerFactory;
  final ProxyController Function() proxyControllerFactory;
  final MihomoConnectionController Function()?
  mihomoConnectionControllerFactory;
  final LogsController Function()? logsControllerFactory;
  final AutomationController Function()? automationControllerFactory;
  final ExtensionsController Function()? extensionsControllerFactory;
  final UpstreamController Function()? upstreamControllerFactory;
  final ExportProxyController Function()? exportProxyControllerFactory;
  final SettingsController Function()? settingsControllerFactory;
  final CertificateController Function()? certificateControllerFactory;
  final AppearanceController appearance;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

final class _SessionGateState extends State<SessionGate> {
  OverviewController? _overviewController;
  DeviceListController? _deviceListController;
  SmsController? _smsController;
  CallsController? _callsController;
  ProxyController? _proxyController;
  MihomoConnectionController? _mihomoConnectionController;
  LogsController? _logsController;
  AutomationController? _automationController;
  ExtensionsController? _extensionsController;
  UpstreamController? _upstreamController;
  ExportProxyController? _exportProxyController;
  SettingsController? _settingsController;
  CertificateController? _certificateController;

  @override
  void initState() {
    super.initState();
    widget.sessionController.addListener(_handleSessionChanged);
    _synchronizeSignedInControllers();
    widget.sessionController.bootstrap();
  }

  @override
  void didUpdateWidget(SessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = !identical(
      oldWidget.sessionController,
      widget.sessionController,
    );
    final ownerDependenciesChanged =
        !identical(
          oldWidget.overviewControllerFactory,
          widget.overviewControllerFactory,
        ) ||
        !identical(
          oldWidget.deviceListControllerFactory,
          widget.deviceListControllerFactory,
        ) ||
        !identical(
          oldWidget.smsControllerFactory,
          widget.smsControllerFactory,
        ) ||
        !identical(
          oldWidget.callsControllerFactory,
          widget.callsControllerFactory,
        ) ||
        !identical(
          oldWidget.proxyControllerFactory,
          widget.proxyControllerFactory,
        ) ||
        !identical(
          oldWidget.mihomoConnectionControllerFactory,
          widget.mihomoConnectionControllerFactory,
        );
    if (sessionChanged || ownerDependenciesChanged) {
      if (sessionChanged) {
        oldWidget.sessionController.removeListener(_handleSessionChanged);
      }
      _disposeSignedInControllers();
      if (sessionChanged) {
        widget.sessionController.addListener(_handleSessionChanged);
      }
      _synchronizeSignedInControllers();
      if (sessionChanged) {
        widget.sessionController.bootstrap();
      }
    }
  }

  @override
  void dispose() {
    widget.sessionController.removeListener(_handleSessionChanged);
    _disposeSignedInControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.sessionController.state;
    return switch (state.status) {
      SessionStatus.booting => const _BootingSession(),
      SessionStatus.signedIn => AndroidOneImsShell(
        sessionController: widget.sessionController,
        overviewController: _overviewController!,
        deviceListController: _deviceListController!,
        deviceDetailControllerFactory: widget.deviceDetailControllerFactory,
        esimControllerFactory: widget.esimControllerFactory,
        smsController: _smsController!,
        callsController: _callsController!,
        proxyController: _proxyController!,
        mihomoConnection: _mihomoConnectionController,
        logsController: _logsController,
        automationController: _automationController,
        extensionsController: _extensionsController,
        upstreamController: _upstreamController,
        exportProxyController: _exportProxyController,
        settingsController: _settingsController,
        certificateController: _certificateController,
        appearance: widget.appearance,
      ),
      SessionStatus.signedOut ||
      SessionStatus.signingIn ||
      SessionStatus.expired ||
      SessionStatus.failed => LoginScreen(controller: widget.sessionController),
    };
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    if (widget.sessionController.state.status != SessionStatus.signedIn) {
      unawaited(
        _smsController?.remoteOtpController?.disconnect() ??
            Future<void>.value(),
      );
    }
    setState(_synchronizeSignedInControllers);
  }

  void _synchronizeSignedInControllers() {
    final signedIn =
        widget.sessionController.state.status == SessionStatus.signedIn;
    if (signedIn && _overviewController == null) {
      _overviewController = widget.overviewControllerFactory();
    }
    if (signedIn && _deviceListController == null) {
      _deviceListController = widget.deviceListControllerFactory();
    }
    if (signedIn && _smsController == null) {
      _smsController = widget.smsControllerFactory();
      _smsController?.startOtpWatch();
    }
    if (signedIn && _callsController == null) {
      _callsController = widget.callsControllerFactory();
    }
    if (signedIn && _proxyController == null) {
      _proxyController = widget.proxyControllerFactory();
    }
    if (signedIn &&
        _mihomoConnectionController == null &&
        widget.mihomoConnectionControllerFactory != null) {
      _mihomoConnectionController = widget.mihomoConnectionControllerFactory!();
    }
    if (signedIn &&
        _logsController == null &&
        widget.logsControllerFactory != null) {
      _logsController = widget.logsControllerFactory!();
    }
    if (signedIn &&
        _automationController == null &&
        widget.automationControllerFactory != null) {
      _automationController = widget.automationControllerFactory!();
    }
    if (signedIn &&
        _extensionsController == null &&
        widget.extensionsControllerFactory != null) {
      _extensionsController = widget.extensionsControllerFactory!();
    }
    if (signedIn &&
        _upstreamController == null &&
        widget.upstreamControllerFactory != null) {
      _upstreamController = widget.upstreamControllerFactory!();
    }
    if (signedIn &&
        _exportProxyController == null &&
        widget.exportProxyControllerFactory != null) {
      _exportProxyController = widget.exportProxyControllerFactory!();
    }
    if (signedIn &&
        _settingsController == null &&
        widget.settingsControllerFactory != null) {
      _settingsController = widget.settingsControllerFactory!();
    }
    if (signedIn &&
        _certificateController == null &&
        widget.certificateControllerFactory != null) {
      _certificateController = widget.certificateControllerFactory!();
    }
    if (!signedIn) {
      _disposeSignedInControllers();
    }
  }

  void _disposeSignedInControllers() {
    _overviewController?.dispose();
    _overviewController = null;
    _deviceListController?.dispose();
    _deviceListController = null;
    _smsController?.dispose();
    _smsController = null;
    _callsController?.dispose();
    _callsController = null;
    _proxyController?.dispose();
    _proxyController = null;
    _mihomoConnectionController?.dispose();
    _mihomoConnectionController = null;
    _logsController?.dispose();
    _logsController = null;
    _automationController?.dispose();
    _automationController = null;
    _extensionsController?.dispose();
    _extensionsController = null;
    _upstreamController?.dispose();
    _upstreamController = null;
    _exportProxyController?.dispose();
    _exportProxyController = null;
    _settingsController?.dispose();
    _settingsController = null;
    _certificateController?.dispose();
    _certificateController = null;
  }
}

final class _BootingSession extends StatelessWidget {
  const _BootingSession();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: SessionGate.bootingKey,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: OneInsets.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(
                  child: OneStatusProgress(
                    label: '正在恢复 OneWIFI 会话',
                    kind: OneProgressKind.circular,
                  ),
                ),
                SizedBox(height: OneSpacing.medium),
                Text('正在恢复 OneWIFI 会话'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
