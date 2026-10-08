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

  /// 按设计稿字号构造文本样式（行高按设计稿 line-height / font-size 换算）。
  static TextStyle ts(
    BuildContext context,
    double designSize,
    FontWeight weight,
    Color color, {
    double lineHeight = 1.6,
  }) {
    return TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: s(context, designSize),
      fontWeight: weight,
      color: color,
      height: lineHeight,
    );
  }
}
