/// 设计 Token 与全局主题。
///
/// **唯一真相**：`docs/design-reference/smart-minutes-app.html` 的 `:root` CSS 变量。
/// 本文件是那些变量的 Dart 映射（见 `docs/DESIGN-SPEC-EXACT.md` 第一节），
/// 旧的 `DESIGN-SPEC.md`（从 ardot 画布推断）已废弃。
///
/// 与旧规格的偏差修正（勿回退）：
/// - 分割线 `#F2E4D6` → **`#F1E7DC`**
/// - 主橙按压 `#C2591F` → **`#E8662A`**
/// - 卡片阴影 → **`rgba(58,42,32,.05)` / y6 / blur18**（不再是暖棕重阴影）
/// - 卡片圆角 28/22/18 → **24 / 20**
/// - 新增正文色 `#4A3A30`、更浅色 `#B8A899`、chip 底 `#FBE9DB`
library;

import 'package:flutter/material.dart';

/// 色板（对齐 HTML `:root`）。
class AppColors {
  const AppColors._();

  /// 页面底（暖米）。
  static const Color bg = Color(0xFFFAF3EC);

  /// 卡片白。
  static const Color card = Color(0xFFFFFFFF);

  /// 主橙（按钮 / 选中 / 强调）。
  static const Color orange = Color(0xFFF0783C);

  /// 主橙按压态。
  static const Color orangeDeep = Color(0xFFE8662A);

  /// 浅橙底（光晕 / 徽标 / 自动滚动标签 / 图标底色）。
  static const Color orangeSoft = Color(0xFFFFF0E3);

  /// chip 底、次级标签底。
  static const Color orangeWash = Color(0xFFFBE9DB);

  /// 标题深棕。
  static const Color ink = Color(0xFF3A2A20);

  /// 正文。
  static const Color body = Color(0xFF4A3A30);

  /// 辅助 / 元信息。
  static const Color muted = Color(0xFF8B7565);

  /// 更浅（占位、禁用）。
  static const Color faint = Color(0xFFB8A899);

  /// 分割线。
  static const Color line = Color(0xFFF1E7DC);

  /// 「已完成」徽标底。
  static const Color greenBg = Color(0xFFEAF4EE);

  /// 「已完成」徽标字。
  static const Color green = Color(0xFF4E9A6A);

  /// 录音红点。
  static const Color red = Color(0xFFE5483C);

  /// 断线 Toast 底色（HTML `.toast`）。
  static const Color toastBg = Color(0xFFFBE3D2);

  /// 普通 Toast 底色（HTML `.toast.plain`）。
  static const Color toastPlain = Color(0xFF3A2A20);

  /// Toast 副文案色（HTML `.toast .t-sub`）。
  static const Color toastSub = Color(0xFFA9703F);

  /// 灰色 chip / 灰环底（HTML `--sp8-bg`）。
  static const Color grayWash = Color(0xFFF0EAE4);

  /// 禁用态占位色（HTML `#s08` 的 `#C9BBAE`）。
  static const Color disabled = Color(0xFFC9BBAE);

  /// 命中高亮底（HTML `#s12 .t-item.hl`）。
  static const Color hitBg = Color(0xFFFFF3E6);

  /// 命中条底（HTML `.hit-bar`）。
  static const Color hitBarBg = Color(0xFFFBE3D2);

  /// 分节灰点（HTML `.sum-card li.g::before`）。
  static const Color dotGray = Color(0xFFC9BBAE);

  /// 关闭按钮色（HTML `.hit-bar .nav` 关闭键）。
  static const Color closeBrown = Color(0xFFC07A4A);

  // ── 兼容别名（避免历史调用点大面积改名）───────────────────────────
  /// [card] 的别名。
  static const Color surface = card;

  /// [orange] 的别名。
  static const Color primary = orange;

  /// [orangeDeep] 的别名。
  static const Color primaryDeep = orangeDeep;

  /// [body] 的别名。
  static const Color ink2 = body;

  /// [orangeSoft] 的别名。
  static const Color soft = orangeSoft;
}

/// 动画时长（全站统一，杜绝硬切闪屏）。
class AppDuration {
  const AppDuration._();

  /// 页面/内容切换的淡入时长：太短看不出过渡，太长显得拖沓。
  static const Duration fade = Duration(milliseconds: 220);
}

/// 圆角（HTML `--radius-card` / `--radius-card2`）。
class AppRadius {
  const AppRadius._();

  /// 大卡片圆角（24）。
  static const double card = 24;

  /// 次级卡片 / 列表卡圆角（20）。
  static const double card2 = 20;

  /// 胶囊（999）。
  static const double pill = 999;

  /// 小卡片（16，Toast / 命中条 / 命中片段）。
  static const double md = 16;

  /// 图标方块（10，设置行图标）。
  static const double sm = 10;

  /// 圆（999）。
  static const double circle = 999;
}

/// 阴影（HTML 里出现的全部 box-shadow，逐一登记）。
class AppShadow {
  const AppShadow._();

  /// 卡片：`0 6px 18px rgba(58,42,32,.05)`。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0D3A2A20), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// TabBar：`0 10px 30px rgba(58,42,32,.10)`。
  static const List<BoxShadow> pill = <BoxShadow>[
    BoxShadow(color: Color(0x1A3A2A20), blurRadius: 30, offset: Offset(0, 10)),
  ];

  /// 圆形图标按钮：`0 2px 8px rgba(58,42,32,.06)`。
  static const List<BoxShadow> circleButton = <BoxShadow>[
    BoxShadow(color: Color(0x0F3A2A20), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// 橙色主按钮：`0 10px 24px rgba(240,120,60,.35)`。
  static const List<BoxShadow> orangeButton = <BoxShadow>[
    BoxShadow(color: Color(0x59F0783C), blurRadius: 24, offset: Offset(0, 10)),
  ];

  /// 麦克风按钮：`0 16px 32px rgba(240,120,60,.38)`。
  static const List<BoxShadow> mic = <BoxShadow>[
    BoxShadow(color: Color(0x61F0783C), blurRadius: 32, offset: Offset(0, 16)),
  ];

  /// 选中 Tab / chip：`0 6px 16px rgba(240,120,60,.35)`。
  static const List<BoxShadow> orangePill = <BoxShadow>[
    BoxShadow(color: Color(0x59F0783C), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// 选中 chip：`0 4px 10px rgba(240,120,60,.3)`。
  static const List<BoxShadow> chipOn = <BoxShadow>[
    BoxShadow(color: Color(0x4DF0783C), blurRadius: 10, offset: Offset(0, 4)),
  ];

  /// 分段控件白片：`0 2px 8px rgba(58,42,32,.08)`。
  static const List<BoxShadow> segment = <BoxShadow>[
    BoxShadow(color: Color(0x143A2A20), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// 头像：`0 4px 12px rgba(240,120,60,.3)`。
  static const List<BoxShadow> avatar = <BoxShadow>[
    BoxShadow(color: Color(0x4DF0783C), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Toast：`0 12px 28px rgba(200,90,30,.22)`。
  static const List<BoxShadow> toast = <BoxShadow>[
    BoxShadow(color: Color(0x38C85A1E), blurRadius: 28, offset: Offset(0, 12)),
  ];

  /// 悬浮 FAB：`0 6px 16px rgba(58,42,32,.15)`。
  static const List<BoxShadow> fab = <BoxShadow>[
    BoxShadow(color: Color(0x263A2A20), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// 空态 CTA：`0 8px 20px rgba(240,120,60,.35)`。
  static const List<BoxShadow> emptyCta = <BoxShadow>[
    BoxShadow(color: Color(0x59F0783C), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

/// 间距（HTML 实测值）。
class AppSpacing {
  const AppSpacing._();

  /// 页面左右边距（20）。
  static const double page = 20;

  /// 最小可点区域（44）。
  static const double minTap = 44;

  /// TabBar 高度（64）。
  static const double tabBar = 64;

  /// TabBar 距底部（12）。
  static const double tabBarBottom = 12;

  /// TabBar 占位总高（64 + 12 + 12 = 88，对应 HTML `.tabbar-spacer`）。
  static const double tabBarSpacer = 88;

  /// 录音页底部占位（78）。
  static const double tabBarSpacerCompact = 78;

  /// 底部 CTA 距底（24）。
  static const double ctaBottom = 24;

  /// 搜索框高度（48）。
  static const double searchBar = 48;

  /// 信息条高度（48）。
  static const double infoBar = 48;
}

/// 字阶（HTML 实测字号；字族统一 Noto Sans SC）。
class AppTextStyles {
  const AppTextStyles._();

  /// 字族（与 `pubspec.yaml` 的 fonts 声明一致）。
  static const String fontFamily = 'NotoSansSC';

  static const TextTheme _base = TextTheme();

  /// 页面大标题（34 / w700）。
  static TextStyle get pageTitle => _make(34, FontWeight.w700, color: AppColors.ink, letterSpacing: 0.5);

  /// 卡内主标题（22 / w700）。
  static TextStyle get cardTitle => _make(22, FontWeight.w700, color: AppColors.ink);

  /// 区块标题（20 / w700）。
  static TextStyle get sectionTitle => _make(20, FontWeight.w700, color: AppColors.ink);

  /// 卡片头部（17 / w700）。
  static TextStyle get cardHead => _make(17, FontWeight.w700, color: AppColors.ink);

  /// 历史卡标题（17 / w600）。
  static TextStyle get itemTitle => _make(17, FontWeight.w600, color: AppColors.ink);

  /// 计时器（46 / w700 / 等宽数字）。
  static TextStyle get clock => _make(46, FontWeight.w700, color: AppColors.ink, letterSpacing: 1);

  /// 统计数值（26 / w700 / 等宽数字）。
  static TextStyle get statValue => _make(26, FontWeight.w700, color: AppColors.ink);

  /// 正文（15 / 行高 1.62）。
  static TextStyle get body =>
      _make(15, FontWeight.w400, color: AppColors.body, height: 1.62);

  /// 摘要正文（15 / 行高 1.75）。
  static TextStyle get abstract =>
      _make(15, FontWeight.w400, color: AppColors.body, height: 1.75);

  /// 分节小标题（15 / w700）。
  static TextStyle get subHead => _make(15, FontWeight.w700, color: AppColors.ink);

  /// 设置项标题（15 / w600）。
  static TextStyle get settingTitle => _make(15, FontWeight.w600, color: AppColors.ink);

  /// 通用 15 号字。
  static TextStyle get body15 => _make(15, FontWeight.w400, color: AppColors.body);

  /// 按钮文字（17 / w700）。
  static TextStyle get button => _make(17, FontWeight.w700, color: Colors.white);

  /// 次级按钮文字（16 / w600）。
  static TextStyle get buttonSecondary => _make(16, FontWeight.w600, color: AppColors.ink);

  /// 强调操作文字（14 / w600，橙色）。
  static TextStyle get action => _make(14, FontWeight.w600, color: AppColors.orange);

  /// 元信息（13）。
  static TextStyle get meta => _make(13, FontWeight.w400, color: AppColors.muted);

  /// 元信息（12）。
  static TextStyle get metaSmall => _make(12, FontWeight.w400, color: AppColors.muted);

  /// 徽标（11 / w600）。
  static TextStyle get badge => _make(11, FontWeight.w600, color: AppColors.orange);

  /// chip（13 / w500）。
  static TextStyle get chip => _make(13, FontWeight.w500, color: AppColors.muted);

  /// 说话人 chip（12 / w500）。
  static TextStyle get speakerChip => _make(12, FontWeight.w500, color: AppColors.muted);

  /// 版本号（12）。
  static TextStyle get version => _make(12, FontWeight.w400, color: AppColors.faint);

  /// 问候语（15）。
  static TextStyle get greeting => _make(15, FontWeight.w400, color: AppColors.muted);

  /// 输入框（14）。
  static TextStyle get input => _make(14, FontWeight.w400, color: AppColors.ink);

  static TextStyle _make(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// 占位：保留对 `TextTheme` 的引用，避免分析器误报未使用。
  static TextTheme get base => _base;
}

/// 构造应用主题。
///
/// `useMaterial3` 保持开启；主色由 [AppColors.orange] 生成，
/// 但所有可见颜色都由组件显式取自 [AppColors]，不依赖 Material 自动推导。
ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.orange,
    brightness: Brightness.light,
    surface: AppColors.card,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: AppTextStyles.fontFamily,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: scheme,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: AppColors.line,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: ThemeData.light().textTheme.apply(fontFamily: AppTextStyles.fontFamily),
  );
}
