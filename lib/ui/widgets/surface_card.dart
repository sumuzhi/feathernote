/// 通用白卡片（HTML `.card`）：圆角 24 或 20 + `rgba(58,42,32,.05)` 阴影。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 白卡片。
class SurfaceCard extends StatelessWidget {
  /// 构造卡片。
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.radius = AppRadius.card,
    this.width,
  });

  /// 内容。
  final Widget child;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  /// 外边距。
  final EdgeInsetsGeometry margin;

  /// 圆角（默认 24；列表卡用 20）。
  final double radius;

  /// 固定宽度（为空时占满父级）。
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadow.card,
      ),
      child: child,
    );
  }
}
