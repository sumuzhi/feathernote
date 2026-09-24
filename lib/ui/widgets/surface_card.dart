/// 白卡容器：统一「白底 + 大圆角 + 暖棕柔和阴影 + 1px 暖色描边」。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 表面卡片。
class SurfaceCard extends StatelessWidget {
  /// 构造卡片。
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.radius = AppRadius.card,
    this.shadows = AppShadow.card,
    this.color = AppColors.surface,
    this.bordered = true,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  /// 内容。
  final Widget child;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  /// 圆角。
  final double radius;

  /// 阴影。
  final List<BoxShadow> shadows;

  /// 底色。
  final Color color;

  /// 是否绘制描边。
  final bool bordered;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 长按回调。
  final VoidCallback? onLongPress;

  /// 无障碍标签。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: bordered ? Border.all(color: AppColors.hairline) : null,
          boxShadow: shadows,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: borderRadius,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
