import 'package:flutter/material.dart';

import '../../../app/appearance_controller.dart';
import '../../../core/state/action_state.dart';
import '../../../core/state/query_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/one_status_hero.dart';
import '../../auth/state/session_controller.dart';
import '../../certificates/presentation/certificates_screen.dart';
import '../../certificates/state/certificate_controller.dart';
import '../../proxy/state/mihomo_connection_controller.dart';
import '../../sms/presentation/widgets/remote_otp_pairing_tile.dart';
import '../../sms/state/sms_controller.dart';
import '../domain/gateway_settings.dart';
import '../state/settings_controller.dart';
import 'widgets/settings_appearance_tiles.dart';
import 'widgets/settings_https_tiles.dart';
import 'widgets/settings_language_tiles.dart';
import 'widgets/settings_license_card.dart';
import 'widgets/settings_mihomo_form.dart';
import 'widgets/settings_sms_tiles.dart';
import 'widgets/settings_vowifi_tiles.dart';

/// 设置页：对标 WEB `Settings.vue`。外观只改本机；其余项走网关。
/// P6 增量入口（扩展 / 出站 / 导出 / 保号 / 日志）只在本页下钻，不进底栏。
final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.sessionController,
    required this.appearance,
    this.settingsController,
    this.mihomo,
    this.smsController,
    this.certificateController,
    this.onOpenLogs,
    this.onOpenAutomation,
    this.onOpenExtensions,
    this.onOpenUpstream,
    this.onOpenExportProxies,
    super.key,
  });

  final SessionController sessionController;
  final AppearanceController appearance;
  final SettingsController? settingsController;
  final MihomoConnectionController? mihomo;
  final SmsController? smsController;
  final CertificateController? certificateController;
  final VoidCallback? onOpenLogs;
  final VoidCallback? onOpenAutomation;
  final VoidCallback? onOpenExtensions;
  final VoidCallback? onOpenUpstream;
  final VoidCallback? onOpenExportProxies;

  static const Key languageZhKey = Key('settings-language-zh');
  static const Key languageEnKey = Key('settings-language-en');
  static const Key systemInfoKey = Key('settings-system-info');
  static const Key entryLogsKey = Key('settings-entry-logs');
  static const Key entryAutomationKey = Key('settings-entry-automation');
  static const Key entryExtensionsKey = Key('settings-entry-extensions');
  static const Key entryUpstreamKey = Key('settings-entry-upstream');
  static const Key entryExportKey = Key('settings-entry-export');

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _license = TextEditingController();
  SettingsSnapshot? _hydrated;
  bool _signingOut = false;
  int _snackedSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.settingsController?.addListener(_onSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.settingsController?.load();
    });
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settingsController, widget.settingsController)) {
      oldWidget.settingsController?.removeListener(_onSettings);
      widget.settingsController?.addListener(_onSettings);
      _hydrated = null;
      widget.settingsController?.load();
    }
  }

  @override
  void dispose() {
    widget.settingsController?.removeListener(_onSettings);
    _license.dispose();
    super.dispose();
  }

  void _onSettings() {
    final controller = widget.settingsController;
    if (controller == null || !mounted) return;
    _hydrate(controller.data);
    if (controller.passwordChanged && !_signingOut) {
      _signingOut = true;
      widget.sessionController.signOut();
    }
    setState(() {});
    _presentNotice();
  }

  void _presentNotice() {
    final settings = widget.settingsController;
    if (settings == null || !mounted) return;
    if (settings.noticeSeq == _snackedSeq) return;
    _snackedSeq = settings.noticeSeq;
    final notice = settings.notice;
    if (notice.isEmpty) return;
    _showSnack(notice, error: settings.noticeError);
  }

  void _showSnack(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? scheme.error : null,
          margin: EdgeInsets.fromLTRB(
            OneSpacing.page,
            0,
            OneSpacing.page,
            OneInsets.scroll(context).bottom,
          ),
        ),
      );
  }

  void _hydrate(SettingsSnapshot snap) {
    if (identical(_hydrated, snap)) return;
    final previous = _hydrated;
    _hydrated = snap;
    if ((previous == null || previous.license.key != snap.license.key) &&
        _license.text != snap.license.key) {
      _license.text = snap.license.key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsController;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.appearance,
        ?widget.smsController?.remoteOtpController,
      ]),
      builder: (context, _) {
        final snap = settings?.data ?? const SettingsSnapshot();
        final loading =
            settings?.snapshot.status == QueryStatus.loading ||
            settings?.snapshot.status == QueryStatus.refreshing;
        return SingleChildScrollView(
          padding: OneInsets.scroll(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const OwPageHead(title: '系统设置', desc: '授权、外观，以及 Mihomo 后端。'),
              if (widget.smsController case final sms?) ...<Widget>[
                const SizedBox(height: OneSpacing.medium),
                RemoteOtpPairingTile(controller: sms),
              ],
              if (loading) ...<Widget>[
                const SizedBox(height: OneSpacing.medium),
                const OneStatusProgress(
                  label: '正在读取设置',
                  kind: OneProgressKind.linear,
                ),
              ],
              const SizedBox(height: OneSpacing.medium),
              SettingsLicenseCard(
                license: snap.license,
                gatewayLicense: snap.gatewayLicense,
                controller: _license,
                busy: settings?.licenseAction.status == ActionStatus.submitting,
                onActivate: settings == null
                    ? null
                    : () => settings.activateLicense(_license.text),
                onDeactivate: settings?.deactivateLicense,
              ),
              const SizedBox(height: OneSpacing.medium),
              SettingsVowifiTiles(
                settings: snap.vowifiMtu,
                busy:
                    settings?.vowifiMtuAction.status == ActionStatus.submitting,
                onChanged: settings?.setVowifiMtu,
              ),
              const SizedBox(height: OneSpacing.medium),
              SettingsSmsTiles(
                settings: snap.smsModem,
                busy:
                    settings?.smsModemAction.status == ActionStatus.submitting,
                onChanged: settings?.setSmsAutoClear,
              ),
              const SizedBox(height: OneSpacing.medium),
              if (widget.mihomo case final mihomo?) ...<Widget>[
                SettingsMihomoForm(controller: mihomo),
                const SizedBox(height: OneSpacing.medium),
              ],
              OwSection(
                title: '外观',
                icon: Icons.tune,
                tone: PlateTone.blue,
                desc: '只改 Board 自己的明暗，不进网关。',
                child: SettingsAppearanceTiles(appearance: widget.appearance),
              ),
              const SizedBox(height: OneSpacing.medium),
              OwSection(
                title: '界面语言',
                icon: Icons.translate,
                tone: PlateTone.purple,
                desc: '写入网关。本包界面仍是简体中文。',
                child: SettingsLanguageTiles(
                  language: snap.language,
                  busy:
                      settings?.languageAction.status ==
                      ActionStatus.submitting,
                  onSelected: settings?.setLanguage,
                  languageZhKey: SettingsScreen.languageZhKey,
                  languageEnKey: SettingsScreen.languageEnKey,
                ),
              ),
              if (widget.certificateController != null) ...<Widget>[
                const SizedBox(height: OneSpacing.medium),
                OwSection(
                  title: '证书',
                  icon: Icons.security_outlined,
                  tone: PlateTone.teal,
                  desc: '网关 HTTPS 证书。',
                  child: CertificatesScreen(
                    controller: widget.certificateController,
                    embedded: true,
                  ),
                ),
              ],
              if (snap.https case final https?) ...<Widget>[
                const SizedBox(height: OneSpacing.medium),
                OwSection(
                  title: 'HTTPS',
                  icon: Icons.lock_outlined,
                  tone: PlateTone.blue,
                  desc: '自签证书，仅开发者模式可用。',
                  child: SettingsHttpsTiles(
                    https: https,
                    busy:
                        settings?.httpsAction.status == ActionStatus.submitting,
                    onChanged: settings?.setHttps,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
