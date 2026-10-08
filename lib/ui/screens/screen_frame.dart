/// 屏幕骨架：内容 + 可选底部 TabBar / 底部 CTA / 悬浮按钮 / 顶部浮层。
///
/// 对齐 HTML `.phone > .app-screen`：每个屏都是「`.scroll` + 绝对定位的
/// TabBar / CTA / FAB / Toast」；系统状态栏安全区由 [SafeArea] 处理。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_tab_bar.dart';

/// 屏幕骨架。
class ScreenFrame extends StatelessWidget {
  /// 构造骨架。
  const ScreenFrame({
    super.key,
    required this.body,
    this.header,
    this.scrollable = true,
    this.tabIndex,
    this.onTabTap,
    this.bottomCta,
    this.topOverlay,
    this.floating,
    this.scrollController,
    this.bottomSpacer = AppSpacing.tabBarSpacer,
  });

  /// 主体内容。
  final Widget body;

  /// 固定头部（不随内容滚动）。
  ///
  /// 放在 `SingleChildScrollView` **之外**、[SafeArea] 之内：导入两屏（屏 14 /
  /// 屏 15）的长列表滚到下面时，左上角的返回按钮必须还点得到，所以顶栏不参与
  /// 滚动。默认 null = 该屏没有固定头部（其余屏行为不变）。
  final Widget? header;

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

    // 用 Material 而不是纯 ColoredBox：TextField / InkWell 等需要 Material 祖先，
    // 页面自己渲染背景（每屏自带 TabBar，不再走 ShellRoute 的 Scaffold）。
    //
    // SizedBox.expand 不能省：本骨架常被放进松约束的 Stack（如 AppToastOverlay），
    // 而内层所有元素都是绝对定位或零宽占位，去掉它整屏宽度会塌成 0
    // （原先是靠已经删除的自绘状态栏那一行把宽度撑开的）。
    return Material(
      color: AppColors.bg,
      child: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            SafeArea(
              top: true,
              bottom: false,
              left: false,
              right: false,
              child: Column(
                children: <Widget>[
                  // 固定头部：在滚动容器之外，不随内容滚动（导入两屏用它保证
                  // 返回按钮常驻）。
                  ?header,
                  Expanded(child: content),
                ],
              ),
            ),
            if (topOverlay != null)
              Positioned(
                top: MediaQuery.viewPaddingOf(context).top + 13,
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
      ),
    );
  }
}
