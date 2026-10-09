/// 顶栏（HTML `.rec-top` / `.doc-top`）：左圆形按钮 + 居中标题/副标题 + 右圆形按钮。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';

/// 页面顶栏。
class AppTopBar extends StatelessWidget {
  /// 构造顶栏。
  const AppTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.onLeading,
    required this.actionIcon,
    required this.onAction,
    this.dimTitle = false,
    this.actionTooltip = '更多',
  });

  /// 标题。
  final String title;

  /// 副标题。
  final String subtitle;

  /// 左侧图标。
  final IconData leadingIcon;

  /// 左侧点击。
  final VoidCallback onLeading;

  /// 右侧图标。
  final IconData actionIcon;

  /// 右侧点击。
  final VoidCallback onAction;

  /// 标题是否半透明（断线态 s06 的「录音中」opacity .28）。
  final bool dimTitle;

  /// 右侧按钮语义文案。
  final String actionTooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 6, AppSpacing.page, 0),
      child: Row(
        children: <Widget>[
          AppCircleButton(icon: leadingIcon, onTap: onLeading, tooltip: '返回'),
          Expanded(
            child: Column(
              children: <Widget>[
                Opacity(
                  opacity: dimTitle ? 0.28 : 1,
                  child: Text(title, style: AppTextStyles.cardHead),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTextStyles.metaSmall),
              ],
            ),
          ),
          AppCircleButton(icon: actionIcon, onTap: onAction, tooltip: actionTooltip),
        ],
      ),
    );
  }
}

/// 橙色圆形头像（HTML `#s01 .avatar` / `#s05 .me-card .ava`）。
class AppAvatar extends StatelessWidget {
  /// 构造头像。
  const AppAvatar({super.key, required this.text, this.size = 44});

  /// 头像文字（「苏」）。
  final String text;

  /// 直径（首页 44，我的页 58）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.orange,
        shape: BoxShape.circle,
        boxShadow: AppShadow.avatar,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: AppTextStyles.itemTitle.copyWith(
          fontSize: size >= 52 ? 23 : 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
