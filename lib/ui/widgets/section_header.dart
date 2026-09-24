/// 区块标题行：左标题 + 右侧「查看全部 ›」。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 区块标题行。
class SectionHeader extends StatelessWidget {
  /// 构造标题行。
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 0),
  });

  /// 标题。
  final String title;

  /// 右侧动作文案。
  final String? actionLabel;

  /// 右侧动作回调。
  final VoidCallback? onAction;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final String? label = actionLabel;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.itemTitle.copyWith(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (label != null && onAction != null)
            _ActionLink(label: label, onTap: onAction!)
          else if (label != null)
            Text(label, style: AppTextStyles.link),
        ],
      ),
    );
  }
}

class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: AppTextStyles.link),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.primaryDeep,
            ),
          ],
        ),
      ),
    );
  }
}
