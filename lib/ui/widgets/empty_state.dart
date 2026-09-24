/// 空态视图：圆形图标托盘 + 标题 + 说明 + 可选动作（用于历史空态 / 搜索无结果）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空态视图。
class EmptyState extends StatelessWidget {
  /// 构造空态。
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  /// 图标。
  final IconData icon;

  /// 标题。
  final String title;

  /// 说明。
  final String? description;

  /// 动作文案。
  final String? actionLabel;

  /// 动作回调。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final String? desc = description;
    final String? action = actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.gap),
          Text(
            title,
            style: AppTextStyles.heroTitle,
            textAlign: TextAlign.center,
          ),
          if (desc != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              desc,
              style: AppTextStyles.meta,
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null && onAction != null) ...<Widget>[
            const SizedBox(height: AppSpacing.gapLg),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: Text(action, style: AppTextStyles.link.copyWith(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}
