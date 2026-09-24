/// 屏幕骨架：状态栏 + 内容 + 可选底部 TabBar / 底部 CTA / 悬浮按钮 / 顶部浮层。
///
/// 对齐 HTML `.phone > .app-screen`：每个屏都是「状态栏 + `.scroll` + 绝对定位的
/// TabBar / CTA / FAB / Toast」。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/status_bar.dart';

/// 屏幕骨架。
class ScreenFrame extends StatelessWidget {
  /// 构造骨架。
  const ScreenFrame({
    super.key,
    required this.body,
    this.scrollable = true,
    this.tabIndex,
    this.onTabTap,
    this.bottomCta,
    this.topOverlay,
    this.floating,
    this.scrollController,
    this.bottomSpacer = AppSpacing.tabBarSpacer,
    this.statusBar = true,
  });

  /// 状态栏之下的主体内容。
  final Widget body;

  /// 主体是否可滚动（录音页 / 空态页为 false）。
  final bool scrollable;

  /// 底部 TabBar 选中下标（null = 不展示 TabBar）。
  final int? tabIndex;

  /// TabBar 点击回调。
  final ValueChanged<int>? onTabTap;

  /// 底部固定 CTA（纪要页 / 转写页）。
  final Widget? bottomCta;

  /// 顶部浮层（断线 Toast）。
  final Widget? topOverlay;

  /// 悬浮按钮（「回到底部」FAB）。
  final Widget? floating;

  /// 滚动控制器（录音页用它自动滚到底）。
  final ScrollController? scrollController;

  /// 内容底部留白（默认 88，录音页 78，CTA 页 100）。
  final double bottomSpacer;

  /// 是否展示状态栏。
  final bool statusBar;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final Widget content = scrollable
        ? SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.only(bottom: bottomSpacer),
            child: body,
          )
        : body;

    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              if (statusBar) const StatusBar(),
              Expanded(child: content),
            ],
          ),
          if (topOverlay != null)
            Positioned(
              top: AppSpacing.statusBar + 13,
              left: AppSpacing.page,
              right: AppSpacing.page,
              child: topOverlay!,
            ),
          if (bottomCta != null)
            Positioned(
              left: AppSpacing.page,
              right: AppSpacing.page,
              bottom: AppSpacing.ctaBottom + bottomInset,
              child: bottomCta!,
            ),
          if (floating != null)
            Positioned(
              right: 34,
              bottom: 238,
              child: floating!,
            ),
          if (tabIndex != null && onTabTap != null)
            AppTabBar(selectedIndex: tabIndex!, onTap: onTabTap!),
        ],
      ),
    );
  }
}
