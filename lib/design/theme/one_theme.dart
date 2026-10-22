import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../one/glass.dart';
import '../one/one_palette.dart';
import '../tokens/one_tokens.dart';

abstract final class OneTheme {
  static SystemUiOverlayStyle systemOverlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      systemNavigationBarIconBrightness: iconBrightness,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData light() => _polish(Glass.apply(_base(oneBlackWhiteLight)));

  static ThemeData dark() => _polish(Glass.apply(_base(oneBlackWhiteDark)));

  static bool isDark(ThemeData theme) => Glass.isDark(theme);

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Montserrat',
  );

  static ThemeData _polish(ThemeData theme) {
    final scheme = theme.colorScheme;
    final dark = Glass.isDark(theme);
    final focusColor = OneColors.focus(scheme.brightness);
    final hairline = BorderSide(
      color: Glass.stroke(scheme, dark),
      width: Glass.strokeWidth,
    );
    final focused = BorderSide(color: focusColor, width: OneFocus.width);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Glass.radiusTile),
      borderSide: hairline,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Glass.radiusTile),
      borderSide: focused,
    );
    final focusAwareSide = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused) ? focused : hairline,
    );
    return theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Glass.fill(scheme, dark),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Glass.space16,
          vertical: Glass.space16,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: OneFocus.width),
        ),
        focusedErrorBorder: focusedBorder,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            OneSizes.minimumTarget,
            OneSizes.minimumTarget,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Glass.radiusTile),
          ),
        ).copyWith(side: focusAwareSide),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(OneSizes.minimumTarget, OneSizes.control),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Glass.radiusTile),
          ),
        ).copyWith(side: focusAwareSide),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            OneSizes.minimumTarget,
            OneSizes.minimumTarget,
          ),
        ).copyWith(side: focusAwareSide),
      ),
    );
  }
}
