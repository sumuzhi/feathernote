/// 设计 token 与全局主题。
///
/// 全部取值来自 `docs/DESIGN-SPEC.md` 第二节的**画布实测值**：
/// 暖奶油底 `#FAF3EC` + 主橙 `#F0783C` + 白卡大圆角 + 暖棕阴影 + Noto Sans SC。
///
/// 注意：这是与 Web 端（Zinc 冷灰 + teal）**完全不同**的一套语言，
/// 不要把 Web 的 token 带进来。
library;

import 'package:flutter/material.dart';

/// 全局字体族名（与 `pubspec.yaml` 的 `fonts.family` 一致）。
const String kFontFamily = 'NotoSansSC';

/// 颜色 token（画布实测）。
abstract final class AppColors {
  /// 页面背景（暖奶油纸感）。
  static const Color bg = Color(0xFFFAF3EC);

  /// 卡片 / TabBar Pill / 分段选中项。
  static const Color surface = Color(0xFFFFFFFF);

  /// 卡片描边 / 分隔线。
  static const Color hairline = Color(0xFFF2E4D6);

  /// 主橙：录音按钮、CTA、选中态。
  static const Color primary = Color(0xFFF0783C);

  /// 主橙浅底：光晕、徽标底、分段 track 选中底。
  static const Color primarySoft = Color(0xFFFFF0E3);

  /// 深橙：徽标文字、链接。
  static const Color primaryDeep = Color(0xFFC2591F);

  /// 分段控件轨道底。
  static const Color trackSoft = Color(0xFFFBF3EC);

  /// 主文字（暖深棕）。
  static const Color ink = Color(0xFF3A2A20);

  /// 次级文字 / 元信息（暖灰褐）。
  static const Color ink2 = Color(0xFF8B7565);

  /// 装饰圆点 / 占位头像。
  static const Color dot = Color(0xFFC9BBAE);

  /// 历史卡片占位头像点。
  static const Color avatarDot = Color(0xFFC4B3A4);

  /// 录音中红点 / 计时圆点。
  static const Color recRed = Color(0xFFE0392B);

  /// 暖棕阴影基色（非灰黑）。
  static const Color shadow = Color(0xFF9E8066);

  /// 说话人 2（绿）。
  static const Color speakerGreen = Color(0xFF4FA46A);

  /// 说话人 2 浅底。
  static const Color speakerGreenSoft = Color(0xFFE9F3EA);

  /// 说话人 3（紫）。
  static const Color speakerPurple = Color(0xFF8B6BB1);

  /// 说话人 3 浅底。
  static const Color speakerPurpleSoft = Color(0xFFEFE9F7);

  /// 说话人 4（蓝）。
  static const Color speakerBlue = Color(0xFF4E7FB8);

  /// 说话人 4 浅底。
  static const Color speakerBlueSoft = Color(0xFFE9EFF7);

  /// 说话人 5（赭）。
  static const Color speakerAmber = Color(0xFFB8860B);

  /// 说话人 5 浅底。
  static const Color speakerAmberSoft = Color(0xFFF7F1E0);

  /// 说话人 6（玫红）。
  static const Color speakerRose = Color(0xFFB0577F);

  /// 说话人 6 浅底。
  static const Color speakerRoseSoft = Color(0xFFF7E9EF);

  /// 说话人辅色（与下标 0–5 对应，下标 0 = 主橙）。
  static const List<Color> speakerPalette = <Color>[
    primary,
    speakerGreen,
    speakerPurple,
    speakerBlue,
    speakerAmber,
    speakerRose,
  ];

  /// 说话人浅底（与 [speakerPalette] 同序）。
  static const List<Color> speakerSoftPalette = <Color>[
    primarySoft,
    speakerGreenSoft,
    speakerPurpleSoft,
    speakerBlueSoft,
    speakerAmberSoft,
    speakerRoseSoft,
  ];

  /// 徽标：已完成（绿）。
  static const Color badgeDoneBg = speakerGreenSoft;
  static const Color badgeDoneFg = Color(0xFF3F7D52);

  /// 徽标：已总结 / 内容较长（橙）。
  static const Color badgeOrangeBg = primarySoft;
  static const Color badgeOrangeFg = primaryDeep;
}

/// 圆角 token。
abstract final class AppRadius {
  /// Hero 卡（待机态录音卡）。
  static const double hero = 28;

  /// 转写卡 / 纪要卡 / 信息卡。
  static const double card = 22;

  /// 历史卡片。
  static const double history = 18;

  /// 麦克风主按钮（正圆，画布标注 64）。
  static const double mic = 64;

  /// 光晕（mic 外圈，画布标注 84）。
  static const double halo = 84;

  /// 麦克风主按钮**实际直径**（由参考图实测：96 = 2×48）。
  static const double micDiameter = 96;

  /// 光晕**实际直径**（由参考图实测：168 = 2×84）。
  static const double haloDiameter = 168;

  /// TabBar Pill。
  static const double pill = 36;

  /// 分段控件轨道 / 选中项。
  static const double track = 21;
  static const double segment = 17;

  /// 徽标。
  static const double badge = 8;

  /// InfoBar / 搜索框。
  static const double infoBar = 14;
  static const double search = 21;

  /// 底部 CTA 大按钮。
  static const double cta = 26;
}

/// 阴影 token（暖棕 + alpha）。
abstract final class AppShadow {
  /// Hero 卡：alpha 0.14，offset y=10，blur 30，spread −6。
  static const List<BoxShadow> hero = <BoxShadow>[
    BoxShadow(
      color: Color(0x249E8066),
      offset: Offset(0, 10),
      blurRadius: 30,
      spreadRadius: -6,
    ),
  ];

  /// 转写卡 / 纪要卡：alpha 0.12，offset y=8，blur 24，spread −6。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F9E8066),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];

  /// TabBar Pill：alpha 0.18，offset y=6，blur 18，spread −2。
  static const List<BoxShadow> pill = <BoxShadow>[
    BoxShadow(
      color: Color(0x2E9E8066),
      offset: Offset(0, 6),
      blurRadius: 18,
      spreadRadius: -2,
    ),
  ];
}

/// 间距 token。
abstract final class AppSpacing {
  /// 页面左右边距。
  static const double page = 20;

  /// 卡片内边距（小）。
  static const double cardSm = 16;

  /// 卡片内边距（标准）。
  static const double card = 20;

  /// 卡片内边距（大）。
  static const double cardLg = 22;

  /// 内容区块纵向节奏（小）。
  static const double gapSm = 12;

  /// 内容区块纵向节奏（标准）。
  static const double gap = 16;

  /// 内容区块纵向节奏（大）。
  static const double gapLg = 22;

  /// TabBar 高度（含 Pill 62 + 上下留白）。
  static const double tabBar = 95;

  /// 最小触控目标。
  static const double minTap = 44;
}

/// 字阶 token（Noto Sans SC）。
///
/// 设计稿标注 400 / 500 / 600 / 700 四档；随包只有 400 / 600 两个字面，
/// 其余由 Flutter 就近匹配：`w500 → 400`、`w700 → 600`。
abstract final class AppTextStyles {
  /// 录音计时器（48 Bold）。
  static const TextStyle timer = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  /// 页面大标题（22 Bold）。
  static const TextStyle pageTitle = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.ink,
  );

  /// 卡片主文案（17 SemiBold）。
  static const TextStyle heroTitle = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink,
  );

  /// 卡片标题（14 SemiBold）。
  static const TextStyle itemTitle = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink,
  );

  /// 片段正文（13 Medium → 随包 400）。
  static const TextStyle body = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.55,
    color: AppColors.ink,
  );

  /// 分段控件 / 小标题（13 SemiBold）。
  static const TextStyle label = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink,
  );

  /// 元信息（12 Regular，暖灰褐）。
  static const TextStyle meta = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.ink2,
  );

  /// 次级元信息（11 Regular）。
  static const TextStyle metaSmall = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.ink2,
  );

  /// 徽标（10 SemiBold）。
  static const TextStyle badge = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 链接 / 强调文字（12 SemiBold，深橙）。
  static const TextStyle link = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.primaryDeep,
  );

  /// 主按钮文字（13 SemiBold，白）。
  static const TextStyle button = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: Colors.white,
  );

  /// 次按钮文字（13 SemiBold，暖棕）。
  static const TextStyle buttonGhost = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.ink,
  );
}

/// 构造全局 [ThemeData]。
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryDeep,
    secondary: AppColors.primaryDeep,
    onSecondary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.trackSoft,
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairline,
    error: AppColors.recRed,
  );

  final TextTheme textTheme = const TextTheme(
    displayLarge: AppTextStyles.timer,
    displayMedium: AppTextStyles.timer,
    headlineSmall: AppTextStyles.pageTitle,
    titleLarge: AppTextStyles.pageTitle,
    titleMedium: AppTextStyles.heroTitle,
    titleSmall: AppTextStyles.itemTitle,
    bodyLarge: AppTextStyles.body,
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.meta,
    labelLarge: AppTextStyles.label,
    labelMedium: AppTextStyles.meta,
    labelSmall: AppTextStyles.badge,
  ).apply(
    fontFamily: kFontFamily,
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kFontFamily,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    textTheme: textTheme,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTextStyles.itemTitle,
    ),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      textStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 11,
        color: Colors.white,
      ),
    ),
  );
}
