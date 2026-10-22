import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/state/action_state.dart';
import '../../../design/tokens/one_tokens.dart';
import '../../../design/widgets/console_layout.dart';
import '../../../design/widgets/glass_dialog.dart';
import '../../../design/widgets/system_controls.dart';
import '../domain/gateway_settings.dart';
import '../state/settings_controller.dart';

Future<void> showNotifyChannelSheet({
  required BuildContext context,
  required SettingsController controller,
  required NotifyChannel channel,
}) {
  return showOneGlassPopup<void>(
    context: context,
    heightFactor: 0.72,
    builder: (context) =>
        NotifyChannelSheet(controller: controller, channel: channel),
  );
}

final class NotifyChannelSheet extends StatefulWidget {
  const NotifyChannelSheet({
    required this.controller,
    required this.channel,
    super.key,
  });

  final SettingsController controller;
  final NotifyChannel channel;

  @override
  State<NotifyChannelSheet> createState() => _NotifyChannelSheetState();
}

final class _NotifyChannelSheetState extends State<NotifyChannelSheet> {
  late NotifyChannelSettings _draft;
  late final TextEditingController _url;
  late final TextEditingController _secret;
  late final TextEditingController _botToken;
  late final TextEditingController _chatId;
  late final TextEditingController _adminId;
  late final TextEditingController _baseUrl;
  late final TextEditingController _proxy;
  late final TextEditingController _token;
  late final TextEditingController _topic;
  late final TextEditingController _pushChannel;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _from;
  late final TextEditingController _to;
  late final TextEditingController _group;
  late final TextEditingController _icon;
  late final TextEditingController _level;
  late final TextEditingController _payload;
  String? _portError;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.data.notifications.of(widget.channel);
    _url = TextEditingController(text: _draft.url);
    _secret = TextEditingController(text: _draft.secret);
    _botToken = TextEditingController(text: _draft.botToken);
    _chatId = TextEditingController(text: _draft.chatId);
    _adminId = TextEditingController(text: _draft.adminId);
    _baseUrl = TextEditingController(text: _draft.baseUrl);
    _proxy = TextEditingController(text: _draft.proxy);
    _token = TextEditingController(text: _draft.token);
    _topic = TextEditingController(text: _draft.topic);
    _pushChannel = TextEditingController(text: _draft.pushChannel);
    _smtpHost = TextEditingController(text: _draft.smtpHost);
    _smtpPort = TextEditingController(text: '${_draft.smtpPort}');
    _username = TextEditingController(text: _draft.username);
    _password = TextEditingController(text: _draft.password);
    _from = TextEditingController(text: _draft.fromAddress);
    _to = TextEditingController(text: _draft.toAddresses);
    _group = TextEditingController(text: _draft.group);
    _icon = TextEditingController(text: _draft.icon);
    _level = TextEditingController(text: _draft.level);
    _payload = TextEditingController(text: _draft.payloadTemplate);
  }

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    _botToken.dispose();
    _chatId.dispose();
    _adminId.dispose();
    _baseUrl.dispose();
    _proxy.dispose();
    _token.dispose();
    _topic.dispose();
    _pushChannel.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    _username.dispose();
    _password.dispose();
    _from.dispose();
    _to.dispose();
    _group.dispose();
    _icon.dispose();
    _level.dispose();
    _payload.dispose();
    super.dispose();
  }

  NotifyChannelSettings _collect() {
    return _draft.copyWith(
      url: _url.text,
      secret: _secret.text,
      botToken: _botToken.text,
      chatId: _chatId.text,
      adminId: _adminId.text,
      baseUrl: _baseUrl.text,
      proxy: _proxy.text,
      token: _token.text,
      topic: _topic.text,
      pushChannel: _pushChannel.text,
      smtpHost: _smtpHost.text,
      smtpPort: int.tryParse(_smtpPort.text.trim()) ?? _draft.smtpPort,
      username: _username.text,
      password: _password.text,
      fromAddress: _from.text,
      toAddresses: _to.text,
      group: _group.text,
      icon: _icon.text,
      level: _level.text,
      payloadTemplate: _payload.text,
    );
  }

  bool _portIsValid() {
    if (widget.channel != NotifyChannel.email) return true;
    final port = int.tryParse(_smtpPort.text.trim());
    return port != null && port >= 1 && port <= 65535;
  }

  bool _validatePort() {
    if (_portIsValid()) {
      if (_portError != null) setState(() => _portError = null);
      return true;
    }
    setState(() => _portError = '端口必须是数字');
    return false;
  }

  bool _tryCommit() {
    if (!_validatePort()) return false;
    final next = _collect();
    widget.controller.patchNotify(widget.channel, next);
    setState(() => _draft = next);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final saving =
            widget.controller.notifyAction.status == ActionStatus.submitting;
        final testing =
            widget.controller.testAction.status == ActionStatus.submitting;
        return LayoutBuilder(
          builder: (context, constraints) {
            final bounded =
                constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
            return ListView(
              shrinkWrap: !bounded,
              padding: EdgeInsets.only(
                left: OneInsets.scroll(context).left,
                right: OneInsets.scroll(context).right,
                top: OneSpacing.medium,
                bottom:
                    MediaQuery.viewInsetsOf(context).bottom + OneSpacing.medium,
              ),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.channel.label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const SystemIcon(Icons.close),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: _draft.enabled,
                  onChanged: (value) {
                    if (!_validatePort()) return;
                    final next = _collect().copyWith(enabled: value);
                    widget.controller.patchNotify(widget.channel, next);
                    setState(() => _draft = next);
                  },
                ),
                ..._fields(),
                if (!widget.channel.canTest)
                  Padding(
                    padding: const EdgeInsets.only(top: OneSpacing.small),
                    child: Text(
                      '此通道不支持连通测试。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: OneSpacing.item),
                Wrap(
                  spacing: OneSpacing.small,
                  runSpacing: OneSpacing.small,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    if (widget.channel.canTest)
                      GlassActionButton(
                        key: const Key('settings-notify-test'),
                        icon: Icons.science_outlined,
                        label: testing ? '测试中…' : '测试',
                        busy: testing,
                        onPressed: saving || testing
                            ? null
                            : () {
                                if (!_tryCommit()) return;
                                widget.controller.testChannel(widget.channel);
                              },
                      ),
                    GlassActionButton(
                      key: const Key('settings-notify-save'),
                      icon: Icons.save_outlined,
                      label: saving ? '保存中…' : '保存通知设置',
                      busy: saving,
                      onPressed: saving || testing
                          ? null
                          : () async {
                              if (!_tryCommit()) return;
                              await widget.controller.saveNotifications();
                            },
                    ),
                    GlassActionButton(
                      label: '完成',
                      onPressed: () {
                        if (!_tryCommit()) return;
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _fields() {
    final channel = widget.channel;
    return switch (channel) {
      NotifyChannel.telegram => <Widget>[
        _field('Bot token', _botToken, obscure: true),
        _field('Chat ID', _chatId),
        _field('Admin ID', _adminId),
        _field('Base URL', _baseUrl, hint: '可空'),
        _field('代理', _proxy, hint: '可空'),
      ],
      NotifyChannel.bark => <Widget>[
        _field('推送 URL', _url),
        _field('分组', _group),
        _field('图标', _icon),
        _field('级别', _level),
      ],
      NotifyChannel.email => <Widget>[
        _field('SMTP 主机', _smtpHost),
        _field(
          '端口',
          _smtpPort,
          keyboard: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          errorText: _portError,
          onChanged: (_) {
            if (_portError != null) setState(() => _portError = null);
          },
        ),
        _field('用户名', _username),
        _field('密码', _password, obscure: true),
        _field('发件人', _from),
        _field('收件人（逗号分隔）', _to),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('SSL'),
          value: _draft.useSsl,
          onChanged: (value) {
            if (!_validatePort()) return;
            final next = _collect().copyWith(useSsl: value);
            widget.controller.patchNotify(widget.channel, next);
            setState(() => _draft = next);
          },
        ),
      ],
      NotifyChannel.pushplus => <Widget>[
        _field('Token', _token, obscure: true),
        _field('Topic', _topic),
        _field('Channel', _pushChannel),
      ],
      NotifyChannel.webhook => <Widget>[
        _field('URL', _url),
        _field('Secret', _secret, obscure: true),
      ],
      NotifyChannel.wecom => <Widget>[
        _field('Webhook URL', _url),
        _field('Payload 模板', _payload),
      ],
      NotifyChannel.onetools => <Widget>[
        const Text('OneTools 远程验证码'),
        const SizedBox(height: OneSpacing.item),
        const Text('请在系统设置顶部「远程验证码」或短信页完成配对。'),
      ],
    };
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    String? hint,
    String? errorText,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OneSpacing.item),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
