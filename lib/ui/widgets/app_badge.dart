/// 小徽标：`已总结` / `已完成` / `内容较长` 等（10px SemiBold，圆角 8）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 徽标色调。
enum BadgeTone {
  /// 橙（已总结 / 内容较长）。
  orange,

  /// 绿（已完成）。
  green,

  /// 灰（中性，如「已暂停」）。
  slate,
}

/// 小徽标。
class AppBadge extends StatelessWidget {
  /// 构造徽标。
  const AppBadge({super.key, required this.label, this.tone = BadgeTone.orange});

  /// 文案。
  final String label;

  /// 色调。
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      BadgeTone.orange => (AppColors.badgeOrangeBg, AppColors.badgeOrangeFg),
      BadgeTone.green => (AppColors.badgeDoneBg, AppColors.badgeDoneFg),
      BadgeTone.slate => (AppColors.trackSoft, AppColors.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: AppTextStyles.badge.copyWith(color: fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
