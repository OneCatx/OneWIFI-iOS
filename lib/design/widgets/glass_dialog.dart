import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../one/glass.dart';
import '../tokens/one_tokens.dart';

Future<bool?> showOneGlassDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => OneGlassDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

/// 二级菜单：屏幕居中的玻璃弹出层。不要用 [showModalBottomSheet]。
///
/// [heightFactor] 为空时按内容高度收，上限约 86% 屏高（表单类菜单）。
Future<T?> showOneGlassPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor = 0.64,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final media = MediaQuery.of(context);
      Widget popup = OneGlassPopupFrame(child: builder(context));
      if (heightFactor != null) {
        popup = SizedBox(
          width: media.size.width,
          height: media.size.height * heightFactor,
          child: popup,
        );
      } else {
        popup = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: media.size.width,
            maxHeight: media.size.height * 0.86,
          ),
          child: popup,
        );
      }
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: popup,
      );
    },
  );
}

final class OneGlassPopupFrame extends StatelessWidget {
  const OneGlassPopupFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Glass.isDark(theme);
    const radius = BorderRadius.all(Radius.circular(Glass.radiusHero));
    final content = Material(type: MaterialType.transparency, child: child);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return ClipRRect(
        borderRadius: radius,
        child: _SystemGlassSurface(child: content),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: Glass.shadow(dark, strong: true),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: Glass.blurPanel,
            sigmaY: Glass.blurPanel,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Glass.dialogFill(theme.colorScheme, dark),
              borderRadius: radius,
              border: Border.all(
                color: Glass.stroke(theme.colorScheme, dark),
                width: Glass.strokeWidth,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

final class OneGlassDialog extends StatelessWidget {
  const OneGlassDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    super.key,
  });

  static const Key cancelTargetKey = Key('one-dialog-cancel-target');
  static const Key confirmTargetKey = Key('one-dialog-confirm-target');

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: OneGlassPopupFrame(
        child: Padding(
          padding: const EdgeInsets.all(Glass.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: Glass.space12),
              Text(message),
              const SizedBox(height: Glass.space16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Glass.space8,
                runSpacing: Glass.space8,
                children: <Widget>[
                  ConstrainedBox(
                    key: cancelTargetKey,
                    constraints: const BoxConstraints(
                      minHeight: OneSizes.minimumTarget,
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(cancelLabel),
                    ),
                  ),
                  ConstrainedBox(
                    key: confirmTargetKey,
                    constraints: const BoxConstraints(
                      minHeight: OneSizes.minimumTarget,
                    ),
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SystemGlassSurface extends StatelessWidget {
  const _SystemGlassSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: UiKitView(viewType: 'onewifi/system_glass_surface'),
        ),
        child,
      ],
    );
  }
}
