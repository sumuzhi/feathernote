/// 应用根组件：主题 + 路由 + 全局 Toast 浮层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/providers/app_providers.dart';
import '../ui/router/app_router.dart';
// routeObserver 从 app_router.dart 导出，无需额外导入。
import '../ui/theme/app_theme.dart';
import '../ui/widgets/app_toast.dart';

/// 全局滚动行为：**关闭过度滑动（overscroll）与滚动条（scrollbars）**。
///
/// 不设置时落到 `MaterialScrollBehavior` 默认值，在 Android 上表现为：
/// - 12+ 的**拉伸回弹**（用户反馈的「果冻感」）；
/// - 滚动时**右缘灰色滚动条**（用户反馈「页面右侧出现 bug」——录音实时列表
///   自动滚动与「我的」页滚动时都会触发）。这里：
/// - `overscroll: false` + `ClampingScrollPhysics` 硬停不回弹；
/// - `scrollbars: false` 不渲染滚动条（对齐 iOS 风格设计稿）。
///
/// 通过 `MaterialApp.scrollBehavior` 全局生效，覆盖历史列表、转写列表、
/// 纪要页、设置页以及横向 chips 等所有可滚动区域。
ScrollBehavior buildAppScrollBehavior() {
  return const MaterialScrollBehavior().copyWith(
    overscroll: false,
    scrollbars: false,
    physics: const ClampingScrollPhysics(),
  );
}

/// 智能会议纪要 App。
class SmartMinutesApp extends StatelessWidget {
  /// 构造根组件。
  const SmartMinutesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '智能会议纪要',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      scrollBehavior: buildAppScrollBehavior(),
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) =>
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: _ToastLayer(child: child ?? const SizedBox.shrink()),
          ),
    );
  }
}

/// 把全局 Toast 包在 MaterialApp 之上（以获得 Directionality / Overlay 环境）。
class _ToastLayer extends ConsumerWidget {
  const _ToastLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToastMessage? message = ref.watch(toastProvider);
    return AppToastOverlay(message: message, child: child);
  }
}
