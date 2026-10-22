import 'package:flutter/material.dart';

import '../core/config/base_url_policy.dart';
import '../design/tokens/one_tokens.dart';
import '../design/widgets/adaptive_glass_dock.dart';
import '../design/widgets/console_layout.dart';
import '../design/widgets/glass_dialog.dart';
import '../design/widgets/one_status_hero.dart';
import '../design/widgets/system_controls.dart';
import '../features/auth/domain/session_user.dart';
import '../features/auth/state/session_controller.dart';
import '../features/automation/presentation/automation_screen.dart';
import '../features/automation/state/automation_controller.dart';
import '../features/calls/presentation/calls_screen.dart';
import '../features/calls/state/calls_controller.dart';
import '../features/certificates/state/certificate_controller.dart';
import '../features/devices/presentation/device_detail_view.dart';
import '../features/devices/presentation/devices_screen.dart';
import '../features/devices/state/device_detail_controller.dart';
import '../features/devices/state/device_list_controller.dart';
import '../features/esim/state/esim_controller.dart';
import '../features/export_proxy/presentation/export_proxy_screen.dart';
import '../features/export_proxy/state/export_proxy_controller.dart';
import '../features/extensions/presentation/extensions_screen.dart';
import '../features/extensions/state/extensions_controller.dart';
import '../features/logs/presentation/logs_screen.dart';
import '../features/logs/state/logs_controller.dart';
import '../features/overview/presentation/overview_screen.dart';
import '../features/overview/state/overview_controller.dart';
import '../features/proxy/presentation/proxy_screen.dart';
import '../features/proxy/state/mihomo_connection_controller.dart';
import '../features/proxy/state/proxy_controller.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/state/settings_controller.dart';
import '../features/sms/presentation/sms_screen.dart';
import '../features/sms/state/sms_controller.dart';
import '../features/upstream/presentation/upstream_screen.dart';
import '../features/upstream/state/upstream_controller.dart';
import 'appearance_controller.dart';

final class AndroidOneImsShell extends StatefulWidget {
  const AndroidOneImsShell({
    required this.sessionController,
    required this.overviewController,
    required this.deviceListController,
    required this.deviceDetailControllerFactory,
    required this.esimControllerFactory,
    required this.smsController,
    required this.callsController,
    required this.proxyController,
    this.mihomoConnection,
    this.logsController,
    this.automationController,
    this.extensionsController,
    this.upstreamController,
    this.exportProxyController,
    this.settingsController,
    this.certificateController,
    required this.appearance,
    super.key,
  });

  static const Key rootKey = Key('android-onewifi-shell');
  static const Key logoutTargetKey = Key('shell-logout-target');
  static const Key originLabelKey = Key('shell-service-origin');
  static const Key settingsTargetKey = Key('shell-settings-target');

  final SessionController sessionController;
  final OverviewController overviewController;
  final DeviceListController deviceListController;
  final DeviceDetailController Function(String deviceId)
  deviceDetailControllerFactory;
  final EsimController Function(String deviceId) esimControllerFactory;
  final SmsController smsController;
  final CallsController callsController;
  final ProxyController proxyController;
  final MihomoConnectionController? mihomoConnection;
  final LogsController? logsController;
  final AutomationController? automationController;
  final ExtensionsController? extensionsController;
  final UpstreamController? upstreamController;
  final ExportProxyController? exportProxyController;
  final SettingsController? settingsController;
  final CertificateController? certificateController;
  final AppearanceController appearance;

  @override
  State<AndroidOneImsShell> createState() => _AndroidOneImsShellState();
}

/// 底栏页签。代理连 Mihomo 的 WiFi Call Selector；通话先占位。
enum _Tab { overview, devices, sms, proxy, calls, settings }

/// 设置页里的二级页（P6 增量下钻），只在设置页签下有效。
enum _ShellOverlay {
  none,
  logs,
  automation,
  extensions,
  upstream,
  exportProxies,
}

final class _AndroidOneImsShellState extends State<AndroidOneImsShell> {
  bool _signingOut = false;
  _ShellOverlay _overlay = _ShellOverlay.none;
  int _selectedIndex = 0;
  DeviceDetailController? _deviceDetailController;
  EsimController? _esimController;

  List<_Tab> get _tabs => const <_Tab>[
    _Tab.overview,
    _Tab.devices,
    _Tab.sms,
    _Tab.proxy,
    _Tab.calls,
    _Tab.settings,
  ];

  _Tab get _tab => _tabs[_selectedIndex.clamp(0, _tabs.length - 1)];

  String get _originLabel {
    final parts = BaseUrlPolicy.split(widget.sessionController.origin);
    return '${parts.host}:${parts.port}';
  }

  String get _username {
    final principal = widget.sessionController.state.principal;
    return principal is SessionUser ? principal.username : 'OneWIFI';
  }

  @override
  void didUpdateWidget(AndroidOneImsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessionController, widget.sessionController) ||
        !identical(
          oldWidget.deviceDetailControllerFactory,
          widget.deviceDetailControllerFactory,
        ) ||
        !identical(
          oldWidget.deviceListController,
          widget.deviceListController,
        ) ||
        !identical(
          oldWidget.esimControllerFactory,
          widget.esimControllerFactory,
        )) {
      _disposeDeviceDetail();
    }
  }

  @override
  void dispose() {
    _disposeDeviceDetail();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _deviceDetailController == null && _overlay == _ShellOverlay.none,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_overlay != _ShellOverlay.none) {
          setState(() => _overlay = _ShellOverlay.none);
          return;
        }
        if (_deviceDetailController != null) _showDeviceList();
      },
      child: Scaffold(
        key: AndroidOneImsShell.rootKey,
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OneSpacing.page,
                  OneSpacing.small,
                  OneSpacing.small,
                  OneSpacing.small,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'OneWIFI',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: OneSpacing.small),
                            Wrap(
                              spacing: OneSpacing.small,
                              runSpacing: OneSpacing.small,
                              children: <Widget>[
                                Nameplate(label: _username, ready: true),
                                Nameplate(
                                  key: AndroidOneImsShell.originLabelKey,
                                  label: _originLabel,
                                  ready: true,
                                ),
                                const Nameplate(label: '在线', ready: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox.square(
                      key: AndroidOneImsShell.logoutTargetKey,
                      dimension: 44,
                      child: IconButton(
                        tooltip: '退出登录',
                        onPressed: _signingOut ? null : _confirmSignOut,
                        icon: _signingOut
                            ? const OneStatusProgress(
                                label: '正在退出登录',
                                kind: OneProgressKind.circular,
                              )
                            : const SystemIcon(Icons.logout),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _content()),
            ],
          ),
        ),
        bottomNavigationBar: AdaptiveGlassDock(
          destinations: <OneDockDestination>[
            for (final tab in _tabs) _destinationFor(tab),
          ],
          selectedIndex: _selectedIndex.clamp(0, _tabs.length - 1),
          onDestinationSelected: _selectDestination,
        ),
      ),
    );
  }

  OneDockDestination _destinationFor(_Tab tab) => switch (tab) {
    _Tab.overview => const OneDockDestination(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: '仪表盘',
    ),
    _Tab.devices => const OneDockDestination(
      icon: Icons.router_outlined,
      selectedIcon: Icons.router,
      label: '设备',
    ),
    _Tab.sms => const OneDockDestination(
      icon: Icons.sms_outlined,
      selectedIcon: Icons.sms,
      label: '短信',
    ),
    _Tab.proxy => const OneDockDestination(
      icon: Icons.public_outlined,
      selectedIcon: Icons.public,
      label: '代理',
    ),
    _Tab.calls => const OneDockDestination(
      icon: Icons.call_outlined,
      selectedIcon: Icons.call,
      label: '通话',
    ),
    _Tab.settings => const OneDockDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
      key: AndroidOneImsShell.settingsTargetKey,
    ),
  };

  Widget _content() {
    switch (_tab) {
      case _Tab.overview:
        return OverviewScreen(controller: widget.overviewController);
      case _Tab.sms:
        return SmsScreen(
          controller: widget.smsController,
          devices: widget.deviceListController,
        );
      case _Tab.proxy:
        return ProxyScreen(controller: widget.proxyController);
      case _Tab.calls:
        return CallsScreen(
          calls: widget.callsController,
          devices: widget.deviceListController,
        );
      case _Tab.settings:
        final overlayPage = _settingsOverlay();
        if (overlayPage != null) return _morePage(child: overlayPage);
        return SettingsScreen(
          sessionController: widget.sessionController,
          appearance: widget.appearance,
          settingsController: widget.settingsController,
          mihomo: widget.mihomoConnection,
          smsController: widget.smsController,
          certificateController: widget.certificateController,
          onOpenLogs: widget.logsController == null
              ? null
              : () => setState(() => _overlay = _ShellOverlay.logs),
          onOpenAutomation: widget.automationController == null
              ? null
              : () => setState(() => _overlay = _ShellOverlay.automation),
          onOpenExtensions: widget.extensionsController == null
              ? null
              : () => setState(() => _overlay = _ShellOverlay.extensions),
          onOpenUpstream: widget.upstreamController == null
              ? null
              : () => setState(() => _overlay = _ShellOverlay.upstream),
          onOpenExportProxies: widget.exportProxyController == null
              ? null
              : () => setState(() => _overlay = _ShellOverlay.exportProxies),
        );
      case _Tab.devices:
        final detail = _deviceDetailController;
        if (detail != null) {
          return DeviceDetailView(
            controller: detail,
            esimController: _esimController,
            onBack: _showDeviceList,
          );
        }
        return DevicesScreen(
          controller: widget.deviceListController,
          onDeviceSelected: _showDeviceDetail,
        );
    }
  }

  void _selectDestination(int index) {
    if (_overlay != _ShellOverlay.none) {
      setState(() {
        _overlay = _ShellOverlay.none;
        _selectedIndex = index;
      });
      return;
    }
    if (index == _selectedIndex) {
      // 再点一次当前页签 = 刷新它；设备详情里再点「设备」= 回列表。
      switch (_tab) {
        case _Tab.overview:
          widget.overviewController.refresh();
        case _Tab.devices:
          if (_deviceDetailController != null) {
            _showDeviceList();
          } else {
            widget.deviceListController.refresh();
          }
        case _Tab.sms:
          widget.smsController.loadContacts();
        case _Tab.proxy:
          widget.proxyController.refresh();
        case _Tab.calls:
          break;
        case _Tab.settings:
          widget.settingsController?.load();
          widget.certificateController?.loadCertificates();
      }
      return;
    }
    _disposeDeviceDetail();
    setState(() => _selectedIndex = index);
  }

  void _showDeviceDetail(String deviceId) {
    _disposeDeviceDetail();
    final detail = widget.deviceDetailControllerFactory(deviceId);
    final EsimController esim;
    try {
      esim = widget.esimControllerFactory(deviceId);
    } catch (_) {
      detail.dispose();
      rethrow;
    }
    setState(() {
      _deviceDetailController = detail;
      _esimController = esim;
    });
  }

  void _showDeviceList() {
    if (_deviceDetailController == null) return;
    setState(_disposeDeviceDetail);
  }

  void _disposeDeviceDetail() {
    _deviceDetailController?.dispose();
    _deviceDetailController = null;
    _esimController?.dispose();
    _esimController = null;
  }

  Widget? _settingsOverlay() {
    return switch (_overlay) {
      _ShellOverlay.none => null,
      _ShellOverlay.logs => widget.logsController == null
          ? null
          : LogsScreen(controller: widget.logsController!),
      _ShellOverlay.automation => widget.automationController == null
          ? null
          : AutomationScreen(controller: widget.automationController!),
      _ShellOverlay.extensions => widget.extensionsController == null
          ? null
          : ExtensionsScreen(controller: widget.extensionsController!),
      _ShellOverlay.upstream => widget.upstreamController == null
          ? null
          : UpstreamScreen(controller: widget.upstreamController!),
      _ShellOverlay.exportProxies => widget.exportProxyController == null
          ? null
          : ExportProxyScreen(controller: widget.exportProxyController!),
    };
  }

  Widget _morePage({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _overlay = _ShellOverlay.none),
            icon: const SystemIcon(Icons.arrow_back),
            label: const Text('返回设置'),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showOneGlassDialog(
      context: context,
      title: '退出登录?',
      message: '本设备上的本地会话将被清除。',
      confirmLabel: '退出登录',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    await widget.sessionController.signOut();
    if (mounted) setState(() => _signingOut = false);
  }
}
