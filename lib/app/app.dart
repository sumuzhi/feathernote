/// 应用根组件：主题 + 路由 + 全局 Toast 浮层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/app_update.dart';
import '../ui/providers/app_providers.dart';
import '../ui/router/app_router.dart';
// routeObserver 从 app_router.dart 导出，无需额外导入。
import '../ui/theme/app_theme.dart';
import '../ui/widgets/app_toast.dart';
import '../ui/widgets/update_dialog.dart';

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
      title: '声羽 FeatherNote',
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
            child: _UpdatePrompt(
              child: _ToastLayer(child: child ?? const SizedBox.shrink()),
            ),
          ),
    );
  }
}

/// 启动期版本更新检查封装。
///
/// 包裹在 Toast 层之外、MaterialApp.builder 之内，因此拥有 Overlay 环境可弹窗。
/// 仅在每次启动（widget 首次挂载）检查一次：拉取远端 manifest 与本地 versionCode
/// 比较，发现更高版本则弹窗；任何失败静默忽略，不阻断启动。
class _UpdatePrompt extends ConsumerStatefulWidget {
  /// 构造检查封装。
  const _UpdatePrompt({required this.child});

  final Widget child;

  @override
  ConsumerState<_UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<_UpdatePrompt> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_checked) return;
    _checked = true;
    final String url = ref.read(appConfigProvider).updateManifestUrl;
    final UpdateDecision decision = await AppUpdateChecker(manifestUrl: url).check();
    if (!mounted) return;
    if (decision.available && decision.remote != null) {
      await showAppUpdateDialog(context, decision.remote!);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 把全局 Toast 包在 MaterialApp 之上（以获得 Directionality / Overlay 环境）。
class _ToastLayer extends ConsumerWidget {
  const _ToastLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToastMessage? message = ref.watch(toastProvider);
    return AppToastOverlay(
      message: message,
      // × 手动关闭（用户要求：toast 挡住顶部操作时可以立刻关掉）。
      onClose: () => ref.read(toastProvider.notifier).clear(),
      child: child,
    );
  }
}
