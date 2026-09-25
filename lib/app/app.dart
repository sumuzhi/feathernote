/// 应用根组件：主题 + 路由 + 全局 Toast 浮层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/providers/app_providers.dart';
import '../ui/router/app_router.dart';
import '../ui/theme/app_theme.dart';
import '../ui/widgets/app_toast.dart';

/// 全局滚动行为：**关闭过度滑动（overscroll）**。
///
/// 不设置时落到 `MaterialScrollBehavior` 默认值，在 Android 12+ 上表现为
/// **拉伸回弹**（用户反馈的「果冻感」）。这里：
/// - `overscroll: false` 去掉拉伸 / 辉光指示器；
/// - `physics: ClampingScrollPhysics()` 让列表到达边界直接硬停，不回弹。
///
/// 通过 `MaterialApp.scrollBehavior` 全局生效，覆盖历史列表、转写列表、
/// 纪要页、设置页以及横向 chips 等所有可滚动区域。
ScrollBehavior buildAppScrollBehavior() {
  return const MaterialScrollBehavior().copyWith(
    overscroll: false,
    physics: const ClampingScrollPhysics(),
  );
}

/// 智能会议纪要 App。
class SmartMinutesApp extends StatefulWidget {
  /// 构造根组件。
  const SmartMinutesApp({super.key});

  @override
  State<SmartMinutesApp> createState() => _SmartMinutesAppState();
}

class _SmartMinutesAppState extends State<SmartMinutesApp> {
  @override
  void initState() {
    super.initState();
    // 全局唯一挂接点：路由每次变化同步进导航历史（供系统返回键「退回上一步」用）。
    appRouter.routeInformationProvider.addListener(_onLocationChanged);
    _onLocationChanged();
  }

  @override
  void dispose() {
    appRouter.routeInformationProvider.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    appNavHistory.sync(appRouter.routeInformationProvider.value.uri.toString());
  }

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
