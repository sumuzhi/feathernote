/// 信息条（圆角 14，浅底）：左侧主信息 + 右侧次要信息。
///
/// 对应设计稿 07 号屏的 InfoBar：`32 分钟 · 3 位说话人` / `1,860 字`。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 信息条。
class AppInfoBar extends StatelessWidget {
  /// 构造信息条。
  const AppInfoBar({
    super.key,
    required this.left,
    this.right,
    this.trailing,
  });

  /// 左侧文案。
  final String left;

  /// 右侧文案。
  final String? right;

  /// 右侧自定义控件（优先于 [right]）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final String? rightText = right;
    final Widget? rightWidget = trailing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.trackSoft,
        borderRadius: BorderRadius.circular(AppRadius.infoBar),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              left,
              style: AppTextStyles.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rightWidget != null)
            rightWidget
          else if (rightText != null)
            Text(rightText, style: AppTextStyles.meta),
        ],
      ),
    );
  }
}
