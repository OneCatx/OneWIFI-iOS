import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/config/base_url_policy.dart';
import '../../../../design/tokens/one_tokens.dart';
import '../../../../design/widgets/choice_toggle.dart';
import '../../../../design/widgets/glass_panel.dart';
import '../../../../design/widgets/one_mark.dart';
import '../../../../design/widgets/one_status_hero.dart';
import '../../../settings/domain/license_code.dart';

/// 表单各控件的定位 Key，测试用。页面按 [LoginForm.keys] 一次传入。
typedef LoginFormKeys = ({
  Key host,
  Key port,
  Key https,
  Key username,
  Key password,
  Key signIn,
  Key retry,
  Key license,
});

final class LoginForm extends StatelessWidget {
  const LoginForm({
    required this.formKey,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.hostFocus,
    required this.portFocus,
    required this.usernameFocus,
    required this.passwordFocus,
    required this.https,
    required this.busy,
    required this.notice,
    required this.originError,
    required this.showRetry,
    required this.portValidator,
    required this.onChanged,
    required this.onHttpsChanged,
    required this.onSubmit,
    required this.onRetry,
    required this.keys,
    this.license,
    this.licenseFocus,
    this.showLicense = false,
    this.licenseError,
    this.onCertificate,
    this.certificateKey,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController host;
  final TextEditingController port;
  final TextEditingController username;
  final TextEditingController password;
  final FocusNode hostFocus;
  final FocusNode portFocus;
  final FocusNode usernameFocus;
  final FocusNode passwordFocus;
  final bool https;
  final bool busy;
  final String? notice;
  final String? originError;
  final bool showRetry;
  final FormFieldValidator<String> portValidator;
  final VoidCallback onChanged;
  final ValueChanged<bool> onHttpsChanged;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;
  final LoginFormKeys keys;
  final TextEditingController? license;
  final FocusNode? licenseFocus;
  final bool showLicense;
  final String? licenseError;
  final VoidCallback? onCertificate;
  final Key? certificateKey;

  @override
  Widget build(BuildContext context) {
    Uri? previewOrigin;
    try {
      previewOrigin = BaseUrlPolicy.fromHostAndPort(
        host: host.text,
        port: port.text,
        https: https,
      );
    } on FormatException {
      previewOrigin = null;
    }
    final publicHttp =
        previewOrigin != null && BaseUrlPolicy.isPublicCleartext(previewOrigin);
    return Form(
      key: formKey,
      child: GlassPanel(
        semanticLabel: 'OneWIFI 登录',
        padding: OneInsets.hero,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OneMark(
                  size: OneSizes.control,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                const SizedBox(height: OneSpacing.medium),
                Semantics(
                  header: true,
                  child: Text(
                    'OneWIFI',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: OneSpacing.small),
                Text(
                  '输入 OneWIFI 主机的 IP 和端口即可连接。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (notice != null) ...<Widget>[
                  const SizedBox(height: OneSpacing.medium),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      notice!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
                const SizedBox(height: OneSpacing.section),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        key: keys.host,
                        controller: host,
                        focusNode: hostFocus,
                        enabled: !busy,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: '主机 / IP'),
                        onChanged: (_) => onChanged(),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入主机名或 IP。'
                            : null,
                      ),
                    ),
                    const SizedBox(width: OneSpacing.item),
                    Expanded(
                      child: TextFormField(
                        key: keys.port,
                        controller: port,
                        focusNode: portFocus,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: '端口'),
                        onChanged: (_) => onChanged(),
                        validator: portValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OneSpacing.item),
                Text('HTTPS', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: OneSpacing.small),
                ChoiceToggle(
                  key: keys.https,
                  value: https,
                  onChanged: busy ? null : onHttpsChanged,
                ),
                Text(
                  '网页开了 HTTPS，这里也打开。自签证书在右上角核对指纹。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (publicHttp) ...<Widget>[
                  const SizedBox(height: OneSpacing.small),
                  Text(
                    '端口转发场景允许使用公网明文 HTTP。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (originError != null) ...<Widget>[
                  Text(
                    originError!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: OneSpacing.item),
                ],
                TextFormField(
                  key: keys.username,
                  controller: username,
                  focusNode: usernameFocus,
                  enabled: !busy,
                  autofillHints: const <String>[AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入用户名。' : null,
                ),
                if (showLicense && license != null) ...<Widget>[
                  const SizedBox(height: OneSpacing.item),
                  TextFormField(
                    key: keys.license,
                    controller: license,
                    focusNode: licenseFocus,
                    enabled: !busy,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\- ]'),
                      ),
                      LengthLimitingTextInputFormatter(
                        LicenseCode.maxInputLength,
                      ),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '激活码',
                      hintText: 'XXXX-XXXX-XXXX-XXXX',
                      errorText: licenseError,
                    ),
                    onChanged: (_) => onChanged(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入激活码。';
                      }
                      return LicenseCode.localError(value);
                    },
                  ),
                ],
                const SizedBox(height: OneSpacing.item),
                TextFormField(
                  key: keys.password,
                  controller: password,
                  focusNode: passwordFocus,
                  enabled: !busy,
                  obscureText: true,
                  autofillHints: const <String>[AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: busy ? null : (_) => onSubmit(),
                  decoration: const InputDecoration(labelText: '密码'),
                  validator: (value) =>
                      value == null || value.isEmpty ? '请输入密码。' : null,
                ),
                const SizedBox(height: OneSpacing.medium),
                SizedBox(
                  key: keys.signIn,
                  height: OneSizes.control,
                  child: FilledButton(
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? Semantics(
                            liveRegion: true,
                            label: '正在登录',
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SizedBox.square(
                                    dimension: OneSizes.icon,
                                    child: OneStatusProgress(
                                      label: '正在登录',
                                      kind: OneProgressKind.circular,
                                    ),
                                  ),
                                  SizedBox(width: OneSpacing.small),
                                  Text('正在登录…'),
                                ],
                              ),
                            ),
                          )
                        : const Text('登录'),
                  ),
                ),
                if (showRetry) ...<Widget>[
                  const SizedBox(height: OneSpacing.small),
                  SizedBox(
                    key: keys.retry,
                    height: OneSizes.minimumTarget,
                    child: TextButton(
                      onPressed: busy ? null : onRetry,
                      child: const Text('重试'),
                    ),
                  ),
                ],
              ],
            ),
            if (onCertificate != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: certificateKey,
                  tooltip: '证书指纹',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : onCertificate,
                  icon: const Icon(Icons.verified_user_outlined, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
