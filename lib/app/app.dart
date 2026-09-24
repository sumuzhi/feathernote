/// 应用根组件：主题 + 路由 + 全局 Toast 浮层。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/providers/app_providers.dart';
import '../ui/router/app_router.dart';
import '../ui/theme/app_theme.dart';
import '../ui/widgets/app_toast.dart';

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
      routerConfig: appRouter,
      builder: (BuildContext context, Widget? child) =>
          _ToastLayer(child: child ?? const SizedBox.shrink()),
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
