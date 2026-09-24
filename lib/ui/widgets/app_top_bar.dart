/// 顶部栏：左侧圆形按钮 + 居中标题/副标题 + 右侧动作。
///
/// 对应设计稿 02（✕ / 录音中·会议模式 / ⚙）、07（‹ / 完整转写 / 🔍）、
/// 11（✕ / 会议纪要·生成于 / 分享）。左右按钮统一 44×44 圆形，满足触控 ≥44。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 顶部圆形按钮。
class AppCircleButton extends StatelessWidget {
  /// 构造圆形按钮。
  const AppCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.color = AppColors.ink,
  });

  /// 图标。
  final IconData icon;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 无障碍提示。
  final String? tooltip;

  /// 图标颜色。
  final Color color;

  @override
  Widget build(BuildContext context) {
    final Widget button = SizedBox(
      width: AppSpacing.minTap,
      height: AppSpacing.minTap,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 顶部栏。
class AppTopBar extends StatelessWidget {
  /// 构造顶部栏。
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon = Icons.close_rounded,
    this.onLeading,
    this.leadingTooltip,
    this.trailing,
    this.trailingIcon,
    this.onTrailing,
    this.trailingTooltip,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 8),
  });

  /// 标题。
  final String title;

  /// 副标题。
  final String? subtitle;

  /// 左侧图标。
  final IconData leadingIcon;

  /// 左侧点击。
  final VoidCallback? onLeading;

  /// 左侧提示。
  final String? leadingTooltip;

  /// 右侧自定义控件（优先于 [trailingIcon]）。
  final Widget? trailing;

  /// 右侧图标。
  final IconData? trailingIcon;

  /// 右侧点击。
  final VoidCallback? onTrailing;

  /// 右侧提示。
  final String? trailingTooltip;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final String? sub = subtitle;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AppCircleButton(
            icon: leadingIcon,
            onTap: onLeading,
            tooltip: leadingTooltip,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.itemTitle.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: AppTextStyles.metaSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: AppSpacing.minTap,
            height: AppSpacing.minTap,
            child: trailing ??
                (trailingIcon == null
                    ? const SizedBox.shrink()
                    : AppCircleButton(
                        icon: trailingIcon!,
                        onTap: onTrailing,
                        tooltip: trailingTooltip,
                      )),
          ),
        ],
      ),
    );
  }
}
