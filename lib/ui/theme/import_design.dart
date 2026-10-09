/// 屏 14 / 屏 15（导入）设计稿专用 Token。
///
/// 取值全部来自 HTML 设计稿源码（`14 · 上传 · 选择文件/index.html`、
/// `15 · 上传 · 处理中（视频分离音轨）/index.html`）里读出的色值与阴影，
/// 与 `AppColors` 的通用色板重叠部分直接复用，新增色值只登记在此处。
library;

import 'package:flutter/material.dart';

import '../utils/design_scale.dart';
import 'app_theme.dart';

/// 导入屏专属视觉常量。
class ImportDesign {
  const ImportDesign._();

  /// 深棕橙（图标 / 次要文字，HTML `#C2591F`）。
  static const Color orangeText = Color(0xFFC2591F);

  /// 音频浅底（HTML `#FFF0E3`，同 [AppColors.orangeSoft]）。
  static const Color audioSoft = Color(0xFFFFF0E3);

  /// 视频浅底（HTML `#EFEBF7`）。
  static const Color videoSoft = Color(0xFFEFEBF7);

  /// 视频图标 / 文字紫（HTML `#6B5A93`）。
  static const Color videoInk = Color(0xFF6B5A93);

  /// 箭头 / 占位点（HTML `#C2A08C`）。
  static const Color chevron = Color(0xFFC2A08C);

  /// 拖拽区描边（HTML `#F2C9A3`）。
  static const Color zoneBorder = Color(0xFFF2C9A3);

  /// 进度条底轨（HTML `#F1E7DC`）。
  static const Color track = Color(0xFFF1E7DC);

  /// 未完成步骤圆底（HTML `#F1E7DC`）。
  static const Color stepIdleBg = Color(0xFFF1E7DC);

  /// 未完成步骤圆心（HTML `#C2A08C`）。
  static const Color stepIdleDot = Color(0xFFC2A08C);

  /// 已完成步骤圆底（HTML `#E9F3ED`）。
  static const Color stepDoneBg = Color(0xFFE9F3ED);

  /// 已完成步骤勾（HTML `#4E9A6A`）。
  static const Color stepDoneInk = Color(0xFF4E9A6A);

  /// 进行中步骤底环（HTML `#FDEEE2`）。
  static const Color stepRingBg = Color(0xFFFDEEE2);

  /// 通用暖棕阴影色 `rgba(158,128,102,.10)`。
  static const Color shadowWarm = Color(0x1A9E8066);

  /// 拖拽区暖棕阴影色 `rgba(158,128,102,.12)`。
  static const Color shadowWarmStrong = Color(0x1F9E8066);

  /// 卡片阴影：`top 6 / blur 8 / rgba(158,128,102,.10)`。
  static List<BoxShadow> cardShadow(BuildContext context) => <BoxShadow>[
        BoxShadow(
          color: shadowWarm,
          blurRadius: s(context, 8),
          offset: Offset(0, s(context, 6)),
        ),
      ];

  /// 拖拽区阴影：`top 8 / blur 12 / rgba(158,128,102,.12)`。
  static List<BoxShadow> zoneShadow(BuildContext context) => <BoxShadow>[
        BoxShadow(
          color: shadowWarmStrong,
          blurRadius: s(context, 12),
          offset: Offset(0, s(context, 8)),
        ),
      ];

  // ── 行高 ────────────────────────────────────────────────────────────────
  // 设计稿每个文本节点的高度都是实测值（如 13px 字对应 19px 行盒），
  // 用「节点高 / 字号」作为 line-height，卡片总高才能和 HTML 逐像素对上
  // （例：屏 15 四步卡 = 18 + 38 + 14 + 49 + 14 + 38 + 14 + 38 + 18 = 241）。

  /// 10px 字 → 14px 行盒（「自动分离音轨」角标）。
  static const double lh10 = 1.4;

  /// 11px 字 → 16px 行盒（meta / 副文案）。
  static const double lh11 = 1.4545;

  /// 11px 字 → 16.5px 行盒（格式列表两行）。
  static const double lh11Lines = 1.5;

  /// 11px 字 → 17.6px 行盒（说明条 / 预计提示，设计稿 line-height:17.6px）。
  static const double lh11Note = 1.6;

  /// 12px 字 → 19.2px 行盒（顶栏下方说明，设计稿 line-height:19.2px）。
  static const double lh12 = 1.6;

  /// 13px 字 → 19px 行盒（步骤标题 / 区块标题）。
  static const double lh13 = 1.4615;

  /// 14px 字 → 22px 行盒（「选择文件」按钮）。
  static const double lh14 = 1.5714;

  /// 14px 字 → 20px 行盒（文件信息卡标题）。
  static const double lh14File = 1.4286;

  /// 15px 字 → 22px 行盒（拖拽区主文案 / 底部按钮）。
  static const double lh15 = 1.4667;

  /// 15px 字 → 19px 行盒（整体进度百分比，设计稿节点高 19）。
  static const double lh15Pct = 1.2667;

  /// 17px 字 → 25px 行盒（页面标题）。
  static const double lh17 = 1.4706;

  /// 设计稿字号 → 全局字阶（[AppTextStyles]）映射。
  ///
  /// 用户要求：导入两屏字号与整个 App 保持一致，不再沿用设计稿的更小字号。
  /// 就近上取全局档（AppTextStyles：badge 11 / metaSmall 12 / meta 13 /
  /// subHead·设置项 15 / input 14 / body·按钮 15 / cardHead 17）：
  /// 10→11、11→12、12→13、13→15（标题类抬到全局 subHead 档）、14→14、15→15、17→17。
  /// 行高倍率（[lh] 常量）保持不变，行盒随字号自然放大。
  static double _globalSize(double designSize) {
    if (designSize <= 10) return 11;
    if (designSize <= 11) return 12;
    if (designSize <= 12) return 13;
    if (designSize <= 13) return 15;
    if (designSize <= 14) return 14;
    if (designSize <= 15) return 15;
    return 17;
  }

  /// 按设计稿字号构造文本样式（字号经 [_globalSize] 映射到全局字阶）。
  static TextStyle ts(
    BuildContext context,
    double designSize,
    FontWeight weight,
    Color color, {
    double lineHeight = lh13,
  }) {
    return TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: s(context, _globalSize(designSize)),
      fontWeight: weight,
      color: color,
      height: lineHeight,
    );
  }
}
