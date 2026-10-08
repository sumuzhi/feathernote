/// 设计稿比例换算（禁止硬编码像素堆叠）。
///
/// HTML 设计稿画布固定 390×844（`body { width:390px;height:844px }` /
/// `.root0 { width:390px;height:844px }`）。设计稿里读出来的 left / top /
/// width / height / 字号 / 间距，一律先经 [s] 按**画布宽度**等比换算成逻辑
/// 像素再参与布局；纵向关系用 `Column` + `SizedBox(height: s(..))` +
/// `Spacer` 表达，只有需要设计稿绝对定位的坐标（如顶栏里左右两个热区）才用
/// `Stack` + `Positioned`。
library;

import 'package:flutter/material.dart';

/// 设计稿画布宽（390）。
const double kDesignCanvasWidth = 390;

/// 设计稿画布高（844）。
const double kDesignCanvasHeight = 844;

/// 设计稿像素 → 逻辑像素：以画布宽度为基准等比缩放。
///
/// 例：`s(context, 20)` 在 390 宽的机上就是 20，在 430 宽的机上是 22.05。
double s(BuildContext context, double designPx) {
  final double width = MediaQuery.sizeOf(context).width;
  if (width <= 0) return designPx;
  return designPx * width / kDesignCanvasWidth;
}
