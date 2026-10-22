import 'dart:ui';

import 'package:flutter/material.dart';

export 'glass_chrome.dart';
export 'glass_surface.dart';

/// 全局「液态玻璃」皮肤 —— 与 eSIM 端（NekokoLPA2 的 MarkBuy 玻璃语言）**同一套质感**。
///
/// OneTools 与 eSIM 是同一家的两个新产品，所以质感数值必须一致：圆角 18、
/// 面板模糊 18 / 栏模糊 24、发丝描边 0.8 宽（浅色 onSurface 混白 / 深色白 .12）、
/// 通透面 .55 浅 / 深色更薄、卡片面 .72 浅 / .62 深。
/// 浅色投影走双层（接触影 + 环境影），避免半透明卡贴死浅底渐变；深色仍是单层柔黑影。
///
/// **颜色各自保留**：这些数值只规定"透多少、圆多少、边多细"，底色一律从当前
/// [ColorScheme] 派生。因此 Tools 保住 One 血统色、eSIM 保住它自己的色，
/// Material You、动态取色、纯黑主题、用户自选主题色全部照旧生效。
///
/// 性能取舍沿用参照项目的结论：卡片数量多，**不给每张卡片套 BackdropFilter**，
/// 靠半透明与描边营造玻璃观感；真模糊留给少数高价值面。
abstract final class Glass {
  // ── 质感数值：与 eSIM 端逐项对齐，改这里等于改两个产品的"像不像一家人" ──

  /// 卡片/面板圆角。
  static const double radiusCard = 18;

  /// 小面（菜单、输入框、磁贴）圆角。
  static const double radiusTile = 14;

  /// 芯片圆角。参照项目用 10（不是 Material 默认的胶囊形）。
  static const double radiusChip = 10;

  /// 门面卡/底部弹层这类"大面"的圆角。
  ///
  /// 此前首页门面卡（[OneStatusHero]）自己写死 28、底部弹层写 `radiusCard + 4`(22)、
  /// 普通卡走 18，三种大小并存，摆在一起就是"圆角曲率不统一"。统一收敛到 22：
  /// 比普通卡略大一档以突出门面地位，但落在同一条圆角标度上，不再是游离的 28。
  static const double radiusHero = radiusCard + 4;

  /// 悬浮底栏内容区高度（不含左右/底部留白与系统手势条）。
  ///
  /// 以 56dp 收紧胶囊，保留图标、标签和 44dp 触达目标的垂直空间，
  /// 让底栏更接近 Android 端的轻量悬浮导航。
  static const double dockHeight = 56;

  /// 悬浮底栏圆角。等于 [dockHeight] 的一半，两端成胶囊。
  /// 只用于底栏 chrome；芯片仍走 [radiusChip]。
  static const double radiusDock = dockHeight / 2;

  /// 岛与屏幕底（含系统手势条之上）的空隙。
  static const double dockBottomGap = 8;

  /// 底栏磨砂。比 [blurBar] 轻，避免 24 的牛奶罩把后面的页面糊成实炭。
  static const double blurDock = 12;

  /// Kyant `LiquidBottomTabs` 容器 4.dp 内边距。指示条在这圈里滑。
  static const double dockTabInset = 4;

  /// 切换中的液态指示条高度（岛 56 - 上下各 4）。
  static const double dockIndicatorHeight = 48;

  // ── 间距标度（8pt 栅格）：全局统一，改这里等于调所有页面的疏密 ──
  //
  // 此前项目里至少三套间距并行（Glass 的 12/18、AppPaddings 的 16、门面卡自带的
  // 24 与各页手写的 fromLTRB），导致"容器框之间过于拥挤"且一二级页宽度对不齐。
  // 统一到这一把标度后，页面左右留白、卡片间距、卡内留白都从同一处取值。
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;

  /// 页面左右外边距：一级页与二级页统一走它，保证内容宽度严格对齐。
  ///
  /// 从原来的 12 提到 16——首页卡此前在列表 12 之外还各自再补 12（实际 24），
  /// 二级页只有 12，两边宽度对不上。现在两边都只留这一层 16，既对齐又更透气。
  static const double pageMargin = 16;

  /// 竖直堆叠的容器框之间的呼吸间距。卡片自身不再各写外边距，一律靠它拉开。
  static const double cardGap = 14;

  /// 卡内统一内边距。门面卡这类大面可在此基础上加一档（用 [space20]）。
  static const double padCard = 16;

  /// 面板模糊强度。
  static const double blurPanel = 18;

  /// 顶栏/底栏这类 chrome 的模糊强度。
  static const double blurBar = 24;

  /// 液态玻璃 chrome 的模糊。比 [blurBar] 轻，避免糊成磨砂牛奶。
  ///
  /// 配方对齐 Backdrop：color filter → blur(≈8–10) → lens。
  /// 列表卡 / Hero / 底栏禁止用这个值。
  static const double blurLiquid = 10;

  /// 透镜：把已模糊的背景相对中心放大的比例。0.04 = 4%。
  static const double liquidRefraction = 0.04;

  static const double strokeWidth = 0.8;

  /// 顶栏与模态面的透明度下限。
  ///
  /// 主题层没法给 AppBar 套 BackdropFilter，而 pinned 的 SliverAppBar 下面
  /// 会有内容滚过；栏面若跟着通透面走，标题就会被内容穿透。这是为可读性
  /// 明示偏离参照项目的一处：栏和模态面更实，其余面按参照数值。
  static const double barAlpha = 0.86;
  static const double modalAlpha = 0.92;

  static bool isDark(ThemeData theme) => theme.brightness == Brightness.dark;

  /// 通透玻璃填充：芯片、输入框、导航栏这类要透出背后色彩的小面。
  static Color fill(ColorScheme scheme, bool dark) => dark
      ? scheme.surfaceContainerHighest.withValues(alpha: 0.22)
      : scheme.surface.withValues(alpha: 0.55);

  /// 卡片/面板填充：可读性优先，对齐参照项目的 .72 / .62。
  ///
  /// 底色沿用应用原本的卡片色 `surfaceContainerLow`（它带着主题色的色调），
  /// 只是加了透明度。换成 `surfaceContainerLowest` 会在浅色模式变成纯白，
  /// 那等于把带色调的卡片改成白卡——就不叫"配色不变"了。
  static Color fillStrong(ColorScheme scheme, bool dark) =>
      scheme.surfaceContainerLow.withValues(alpha: dark ? 0.62 : 0.72);

  /// 顶栏/底栏填充：比卡片更实，保证标题不被滚动内容穿透。
  ///
  /// 这是给**主题层**的栏用的——那里没法套 [BackdropFilter]，只能靠不透明度硬顶。
  /// 有真模糊的栏请用 [blurredBarFill]。
  static Color barFill(ColorScheme scheme, bool dark) => dark
      ? scheme.surfaceContainerLow.withValues(alpha: barAlpha)
      : scheme.surface.withValues(alpha: barAlpha);

  /// 有真模糊的栏用的填充：可以通透得多，但仍留出可读性余量。
  ///
  /// 参照项目的同类面是白 .55 / .06；我在暗色留厚一点，因为这里的 pinned 栏
  /// 下面会有长列表快速滚过，而本机无设备可实测。
  static Color blurredBarFill(ColorScheme scheme, bool dark) => dark
      ? scheme.surfaceContainerHighest.withValues(alpha: 0.34)
      : scheme.surface.withValues(alpha: 0.60);

  /// 液态玻璃底栏填充。深色用白罩，不用 121212——没有 RuntimeShader 时黑罩再薄也是炭块。
  static Color liquidDockFill(ColorScheme scheme, bool dark) {
    final tint = dark || isNeutralAccent(scheme)
        ? Colors.white
        : scheme.surface;
    return tint.withValues(alpha: dark ? 0.06 : 0.12);
  }

  /// 选中胶囊：Kyant 静止面是浅黑 10% / 深白 10%，不是一块实心强调色方。
  static Color liquidDockIndicatorFill(ColorScheme scheme, bool dark) => dark
      ? Colors.white.withValues(alpha: 0.10)
      : scheme.onSurface.withValues(alpha: 0.08);

  /// 液态玻璃可读性罩：比 [fillStrong] 透，让折射后的背景露出来。
  ///
  /// 彩色主题叠一层很低的 primary，相当于 Backdrop 的 vibrancy；
  /// 中性黑白不染色，避免把玻璃抹灰。
  static Color liquidFill(ColorScheme scheme, bool dark) {
    final base = blurredBarFill(scheme, dark);
    if (isNeutralAccent(scheme)) return base;
    return Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? 0.10 : 0.06),
      base,
    );
  }

  /// 顶边高光 + 底边内阴影：没有 RuntimeShader 时的透镜高光替代。
  static LinearGradient liquidHighlight(bool dark) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: dark
          ? <Color>[
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.12),
            ]
          : <Color>[
              Colors.white.withValues(alpha: 0.38),
              Colors.white.withValues(alpha: 0.06),
              Colors.black.withValues(alpha: 0.05),
            ],
      stops: const <double>[0, 0.42, 1],
    );
  }

  /// 液态取样滤镜：先模糊，再绕中心轻微放大（透镜）。
  ///
  /// [size] 未知或空时只返回模糊，避免无限约束下用错矩阵原点。
  static ImageFilter liquidBackdropFilter(
    Size size, {
    double blur = blurLiquid,
    double refraction = liquidRefraction,
  }) {
    final blurFilter = ImageFilter.blur(
      sigmaX: blur,
      sigmaY: blur,
      tileMode: TileMode.clamp,
    );
    if (size.isEmpty || size.isInfinite || refraction <= 0) {
      return blurFilter;
    }
    final matrix = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(1.0 + refraction, 1.0 + refraction, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
    return ImageFilter.compose(
      inner: blurFilter,
      outer: ImageFilter.matrix(matrix.storage),
    );
  }

  /// 模态面（底部弹层/抽屉/菜单）：内容盖在花哨界面上，最需要实。
  static Color modalFill(ColorScheme scheme, bool dark) =>
      scheme.surfaceContainerLow.withValues(alpha: modalAlpha);

  /// 对话框透明度。背后有真模糊撑着可读性，
  /// 所以可以比"没有模糊时"更透一点，让人真的看见玻璃。
  static const double dialogAlpha = 0.88;

  static Color dialogFill(ColorScheme scheme, bool dark) =>
      scheme.surfaceContainerLow.withValues(alpha: dialogAlpha);

  /// 发丝描边：暗色用白高光折光；浅色把一点 [ColorScheme.onSurface] 混进白边，
  /// 否则纯白 0.40 描边会在浅底上消失，卡片糊进背景。
  static Color stroke(ColorScheme scheme, bool dark) => dark
      ? Colors.white.withValues(alpha: 0.12)
      : Color.alphaBlend(
          Colors.white.withValues(alpha: 0.55),
          scheme.onSurface.withValues(alpha: 0.10),
        );

  /// 柔投影：让玻璃面浮在渐变底之上，而不是贴在上面。
  ///
  /// 深色保持单层柔黑影（卡片 blur 18 / 偏移 (0,8)，强投影 blur 22 / (0,10)）。
  /// 浅色改为双层：贴边接触影 + 稍远环境影——单层 6–8% 在白底渐变上几乎看不见。
  /// 浅色整体压深（接触影 .08/.10，环境影 .16/.20）：白底上原来的 .05/.11
  /// 只剩一圈若有若无的灰边，容器框浮不起来。
  static List<BoxShadow> shadow(bool dark, {bool strong = false}) {
    if (dark) {
      return <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: strong ? 0.32 : 0.28),
          blurRadius: strong ? 22 : 18,
          offset: Offset(0, strong ? 10 : 8),
        ),
      ];
    }
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: strong ? 0.10 : 0.08),
        blurRadius: strong ? 8 : 6,
        offset: Offset(0, strong ? 3 : 2),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: strong ? 0.20 : 0.16),
        blurRadius: strong ? 28 : 22,
        offset: Offset(0, strong ? 12 : 10),
      ),
    ];
  }

  /// 应用底色渐变。
  ///
  /// 玻璃必须有东西可透，否则半透明只会显得发灰；这层渐变就是"可透的东西"。
  /// 取色方式：把主题主色以极低透明度混进 surface —— 既有层次，又完全跟随
  /// 用户当前配色。纯黑主题（AMOLED）例外：一点都不染，保住真黑。
  static LinearGradient backdrop(ColorScheme scheme, bool dark) {
    final pureBlack = dark && scheme.surface == const Color(0xFF000000);
    if (pureBlack) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[scheme.surface, scheme.surface],
      );
    }

    // One 家族的黑白色板没有色相可染，拿近黑的 primary 去混只会把整面背景
    // 抹灰。中性配色改走亮度差：顶亮底沉，像光从上方打下来——层次仍在，
    // 玻璃依旧有东西可透，但不会脏。
    if (isNeutralAccent(scheme)) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? <Color>[scheme.surfaceContainerHigh, scheme.surface]
            : <Color>[scheme.surfaceContainerLowest, scheme.surfaceContainer],
      );
    }

    final top = Color.alphaBlend(
      scheme.primary.withValues(alpha: dark ? 0.10 : 0.07),
      scheme.surface,
    );
    final bottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: dark ? 0.05 : 0.03),
      scheme.surface,
    );
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[top, bottom],
    );
  }

  /// 强调色。primary 为纯白时不能拿来画图标/指示条，改走 onSurface。
  static Color accent(ColorScheme scheme) {
    if (scheme.primary.computeLuminance() > 0.7) return scheme.onSurface;
    return scheme.primary;
  }

  /// 强调色是否几乎没有色相（One 黑白、灰阶主题这类）。
  static bool isNeutralAccent(ColorScheme scheme) =>
      HSLColor.fromColor(scheme.primary).saturation < 0.15;

  /// 玻璃面装饰（配合 [GlassPanel] 或直接给 Container 用）。
  static BoxDecoration decoration(
    ColorScheme scheme,
    bool dark, {
    double radius = radiusCard,
    bool strong = true,
  }) => BoxDecoration(
    color: strong ? fillStrong(scheme, dark) : fill(scheme, dark),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: stroke(scheme, dark), width: strokeWidth),
    boxShadow: shadow(dark),
  );

  /// 给已有主题套上玻璃皮：只改「面」的通透度、描边与圆角，不动 [ColorScheme]。
  ///
  /// 挂在 `buildObtainiumTheme` 的出口，因此全应用（含上游 Obtainium 自己的
  /// 几十个页面）一次性生效，不必逐页改。
  static ThemeData apply(ThemeData base) {
    final scheme = base.colorScheme;
    final dark = base.brightness == Brightness.dark;
    final glassStroke = stroke(scheme, dark);
    final panel = fillStrong(scheme, dark);
    final sheer = fill(scheme, dark);
    final modal = modalFill(scheme, dark);
    final bar = barFill(scheme, dark);
    final hairline = BorderSide(color: glassStroke, width: strokeWidth);

    RoundedSuperellipseBorder shape(double r) => RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(r),
      side: hairline,
    );

    return base.copyWith(
      // 透出底部渐变——玻璃的前提。只放开 Scaffold 背景：canvasColor 是一堆
      // 隐式 Material 面的默认色，一并透明会让它们直接漏底、文字浮在渐变上。
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: base.cardTheme.copyWith(
        color: panel,
        // 浅色给 1 档投影，避免主题 Card 贴死浅底；暗色仍靠发丝边、elevation 0，
        // 免得大面积黑影糊在深色渐变上。阴影色与 [shadow] 的浅色环境影同档，
        // 否则主题 Card 会比玻璃卡明显淡一截。
        elevation: dark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.14 : 0.20),
        surfaceTintColor: Colors.transparent,
        // 全局「框」以首页那张基准卡（PermissionSummaryCard，走 GlassPanel）为准：
        // 它用的是普通圆角 circular(18)，而 shape() 是超椭圆 squircle。此前普通 Card
        // 走 squircle、基准卡走 circular，两种框摆一起圆角不一样。这里让所有 Card
        // 也走 circular(18)+同一条发丝描边，与基准卡对齐；填充色 panel 本就同源。
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: hairline,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: dialogFill(scheme, dark),
        surfaceTintColor: Colors.transparent,
        shape: shape(radiusCard + 4),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: modal,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: modal,
      ),
      // 顶栏用较实的玻璃填充：真磨砂必须逐页包 BackdropFilter，主题层给不了；
      // 若跟着通透面走，pinned 顶栏下滚过的内容会把标题穿透。
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: bar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: bar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // M3 默认 secondaryContainer 灰条会在底栏中间画出一块实心。
        // 选中态由 GlassDock 自己的液态指示条画，主题层指示条必须透明。
        indicatorColor: Colors.transparent,
      ),
      bottomAppBarTheme: base.bottomAppBarTheme.copyWith(
        color: bar,
        elevation: 0,
      ),
      drawerTheme: base.drawerTheme.copyWith(
        backgroundColor: modal,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: modal,
        surfaceTintColor: Colors.transparent,
        shape: shape(radiusTile),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(modal),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(shape(radiusTile)),
        ),
      ),
      expansionTileTheme: base.expansionTileTheme.copyWith(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
      searchBarTheme: base.searchBarTheme.copyWith(
        backgroundColor: WidgetStatePropertyAll(panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(hairline),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: sheer,
        side: hairline,
        shape: shape(radiusChip),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: sheer,
      ),
      // 分割线不能用玻璃描边那个白：它是给面板边缘做折光的，
      // 画在浅色内容里几乎看不见。这里仍走主题的 outlineVariant。
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant.withValues(alpha: dark ? 0.45 : 0.65),
        thickness: 0.5,
      ),
    );
  }
}
