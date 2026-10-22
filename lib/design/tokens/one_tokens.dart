import 'package:flutter/material.dart';

import '../one/glass.dart';
import '../one/one_palette.dart';

/// Compatibility aliases over the Ultra palette and [Glass] scale.
/// Screens may keep using these names; values are the OneIms Ultra source.
abstract final class OneColors {
  static const Color lightBackground = Color(0xFFF9F9FF);
  static const Color lightBackgroundLift = Colors.white;
  static const Color lightInk = oneInk;
  static const Color lightMuted = Color(0xFF44474F);

  static const Color darkBackground = Color(0xFF111318);
  static const Color darkBackgroundLift = Color(0xFF191C20);
  static const Color darkInk = Color(0xFFE2E2E9);
  static const Color darkMuted = Color(0xFFC4C6D0);

  static const Color negative = Color(0xFFBA1A1A);
  static const Color transparent = Color(0x00000000);

  static Color glass(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark ? oneBlackWhiteDark : oneBlackWhiteLight;
    return Glass.fill(scheme, dark);
  }

  static Color hairline(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark ? oneBlackWhiteDark : oneBlackWhiteLight;
    return Glass.stroke(scheme, dark);
  }

  static Color focus(Brightness brightness) =>
      brightness == Brightness.dark ? Colors.white : oneInk;
}

abstract final class OneFocus {
  static const double width = 2;
  static const double offset = 2;
  static const double overlayOpacity = 0.16;
}

abstract final class OneSpacing {
  static const double hairline = Glass.strokeWidth;
  static const double nano = Glass.space2;
  static const double tight = Glass.space6;
  static const double micro = Glass.space4;
  static const double small = Glass.space8;
  static const double item = Glass.space12;
  static const double medium = Glass.space16;
  static const double page = Glass.pageMargin;
  static const double section = Glass.space24;
  static const double large = 36;
}

abstract final class OneRadii {
  static const double control = Glass.radiusTile;
  static const double panel = Glass.radiusCard;
  static const double hero = Glass.radiusHero;
  static const double dock = Glass.radiusDock;
}

abstract final class OneSizes {
  static const double minimumTarget = 44;
  static const double control = 52;
  static const double dock = Glass.dockHeight;
  static const double icon = 22;
}

abstract final class OneInsets {
  static const EdgeInsets page = EdgeInsets.symmetric(
    horizontal: Glass.pageMargin,
    vertical: Glass.space16,
  );
  static const EdgeInsets panel = EdgeInsets.all(Glass.padCard);
  static const EdgeInsets hero = EdgeInsets.all(Glass.space24);
  static const EdgeInsets dock = EdgeInsets.all(Glass.space8);

  static EdgeInsets scroll(BuildContext context) => EdgeInsets.fromLTRB(
    Glass.pageMargin,
    Glass.space16,
    Glass.pageMargin,
    glassDockScrollPadding(context),
  );
}
