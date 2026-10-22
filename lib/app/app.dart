import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme/one_theme.dart';
import '../design/widgets/glass_backdrop.dart';
import '../features/calls/state/calls_controller.dart';
import '../features/certificates/state/certificate_controller.dart';
import '../features/devices/state/device_detail_controller.dart';
import '../features/devices/state/device_list_controller.dart';
import '../features/esim/state/esim_controller.dart';
import '../features/overview/state/overview_controller.dart';
import '../features/proxy/state/mihomo_connection_controller.dart';
import '../features/proxy/state/proxy_controller.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/sms/data/sms_otp_sink.dart';
import '../features/sms/state/sms_controller.dart';
import 'app_dependencies.dart';
import 'appearance_controller.dart';
import 'session_gate.dart';

final class OneWifiApp extends StatefulWidget {
  const OneWifiApp({this.dependencies, super.key});

  final AppDependencies? dependencies;

  @override
  State<OneWifiApp> createState() => _OneWifiAppState();
}

final class _OneWifiAppState extends State<OneWifiApp> {
  late AppDependencies _dependencies;
  late bool _ownsDependencies;
  final AppearanceController _appearance = AppearanceController();
  late OverviewController Function() _overviewFactory;
  late DeviceListController Function() _deviceListFactory;
  late DeviceDetailController Function(String deviceId) _deviceDetailFactory;
  late EsimController Function(String deviceId) _esimFactory;
  late SmsController Function() _smsFactory;
  late CallsController Function() _callsFactory;
  late ProxyController Function() _proxyFactory;
  late MihomoConnectionController Function() _mihomoFactory;
  late SettingsController Function() _settingsFactory;
  late CertificateController Function() _certificateFactory;

  @override
  void initState() {
    super.initState();
    _ownsDependencies = widget.dependencies == null;
    _dependencies = widget.dependencies ?? _productionDependencies();
    _bindFactories();
  }

  @override
  void didUpdateWidget(OneWifiApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      if (_ownsDependencies) _dependencies.dispose();
      _ownsDependencies = widget.dependencies == null;
      _dependencies = widget.dependencies ?? _productionDependencies();
      _bindFactories();
    }
  }

  void _bindFactories() {
    _overviewFactory = _dependencies.createOverviewController;
    _deviceListFactory = _dependencies.createDeviceListController;
    _deviceDetailFactory = _dependencies.createDeviceDetailController;
    _esimFactory = _dependencies.createEsimController;
    _smsFactory = _dependencies.createSmsController;
    _callsFactory = _dependencies.createCallsController;
    _proxyFactory = _dependencies.createProxyController;
    _mihomoFactory = _dependencies.createMihomoConnectionController;
    _settingsFactory = _dependencies.createSettingsController;
    _certificateFactory = _dependencies.createCertificateController;
  }

  @override
  void dispose() {
    if (_ownsDependencies) _dependencies.dispose();
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) {
        return MaterialApp(
          title: 'OneWIFI',
          debugShowCheckedModeBanner: false,
          theme: OneTheme.light(),
          darkTheme: OneTheme.dark(),
          themeMode: _appearance.mode,
          builder: (context, child) {
            final theme = Theme.of(context);
            final reducedMotion = MediaQuery.of(context).disableAnimations;
            final media = MediaQuery.of(context);
            final textScale = Platform.isIOS ? 0.58 : 0.7;
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Theme(
                data: reducedMotion
                    ? theme.copyWith(splashFactory: NoSplash.splashFactory)
                    : theme,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: OneTheme.systemOverlayStyle(
                    MediaQuery.platformBrightnessOf(context),
                  ),
                  child: GlassBackdrop(child: child ?? const SizedBox.shrink()),
                ),
              ),
            );
          },
          home: SessionGate(
            sessionController: _dependencies.sessionController,
            overviewControllerFactory: _overviewFactory,
            deviceListControllerFactory: _deviceListFactory,
            deviceDetailControllerFactory: _deviceDetailFactory,
            esimControllerFactory: _esimFactory,
            smsControllerFactory: _smsFactory,
            callsControllerFactory: _callsFactory,
            proxyControllerFactory: _proxyFactory,
            mihomoConnectionControllerFactory: _mihomoFactory,
            logsControllerFactory: _dependencies.createLogsController,
            automationControllerFactory:
                _dependencies.createAutomationController,
            extensionsControllerFactory:
                _dependencies.createExtensionsController,
            upstreamControllerFactory: _dependencies.createUpstreamController,
            exportProxyControllerFactory:
                _dependencies.createExportProxyController,
            settingsControllerFactory: _settingsFactory,
            certificateControllerFactory: _certificateFactory,
            appearance: _appearance,
          ),
        );
      },
    );
  }
}

AppDependencies _productionDependencies() =>
    AppDependencies(otpSink: NativeSmsOtpSink());
