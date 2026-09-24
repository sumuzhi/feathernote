/// 区块标题行（HTML `#s01 .recent .hd`）：左侧标题 + 右侧橙色链接。
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
  });

  /// 标题。
  final String title;

  /// 右侧链接文案（如「查看全部 ›」）。
  final String? actionLabel;

  /// 右侧链接回调。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(title, style: AppTextStyles.sectionTitle),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(actionLabel!, style: AppTextStyles.action),
              ),
            ),
          ),
      ],
    );
  }
}
