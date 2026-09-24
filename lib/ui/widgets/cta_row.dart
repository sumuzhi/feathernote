/// 底部动作行（设计稿 07 的「复制全文 / 导出 Markdown」、11 的「导出纪要 + 书签」）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 底部 CTA 行：横向排列若干按钮，间距 12。
class CtaRow extends StatelessWidget {
  /// 构造 CTA 行。
  const CtaRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.page, 10, AppSpacing.page, 10),
    this.gap = 12,
  });

  /// 子按钮（可用 `Expanded` 包裹以均分宽度）。
  final List<Widget> children;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  /// 间距。
  final double gap;

  @override
  Widget build(BuildContext context) {
    final List<Widget> spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(width: gap));
      spaced.add(children[i]);
    }
    return Padding(
      padding: padding,
      child: Row(children: spaced),
    );
  }
}

/// 底部固定区域：给内容加上**背景色 + 上边界过渡**，避免滚动内容透出。
///
/// 底部同时计入安全区（`MediaQuery.viewPadding.bottom`）。
class BottomBar extends StatelessWidget {
  /// 构造底部区域。
  const BottomBar({super.key, required this.child, this.color = AppColors.bg});

  /// 内容。
  final Widget child;

  /// 底色。
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: SafeArea(
        top: false,
        child: child,
      ),
    );
  }
}
