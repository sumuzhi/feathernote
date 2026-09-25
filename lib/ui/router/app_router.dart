/// 路由表。
///
/// - 三个 Tab 页（录音 `/`、历史 `/history`、我的 `/profile`）各自渲染底部
///   TabBar（对齐 HTML 每屏自带 `.tabbar` 的结构），因此**不使用 ShellRoute**；
/// - 纪要页 `/meeting/:id` 与完整转写页 `/meeting/:id/transcript` 是压栈页，
///   底部为 CTA 而非 TabBar（对齐屏 03 / 07 / 11 / 12）；
/// - `/gallery`（屏幕目录）**仅 debug 构建注册**，用于逐屏对照评审。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/meeting.dart';
import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/meeting_page.dart';
import '../pages/profile_page.dart';
import '../pages/transcript_page.dart';
import '../providers/app_providers.dart';
import '../screens/gallery_screen.dart';
import '../widgets/app_toast.dart';

/// 全局路由。
///
/// **导航形态**：Tab 三页之间用 `go()` 平铺切换；详情页（纪要 / 转写 /
/// 屏幕目录）一律 `push()` 压栈 —— 系统返回键在压栈页由 Navigator 原生
/// pop，天然「返回上一步」（见 [AppBackHandler]）。
///
/// **统一页面过渡**：所有路由都走 [_transitionPage]（淡入 + 8px 上移，220ms）。
/// 此前用默认 `builder`，切页是"硬切"，特别是「完整转写 → 生成纪要 → 纪要页」
/// 这条链路会明显闪一下；全局加过渡后不再有裸切帧。
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'record',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _transitionPage(state, const HomePage()),
    ),
    GoRoute(
      path: '/history',
      name: 'history',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _transitionPage(state, const HistoryPage()),
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _transitionPage(state, const ProfilePage()),
    ),
    GoRoute(
      path: '/meeting/:id',
      name: 'meeting',
      pageBuilder: (BuildContext context, GoRouterState state) => _transitionPage(
        state,
        MeetingPage(meetingId: state.pathParameters['id'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/meeting/:id/transcript',
      name: 'transcript',
      // `extra` 携带来源页已加载的 [Meeting]，供转写页首帧直接渲染（消除闪烁）。
      pageBuilder: (BuildContext context, GoRouterState state) => _transitionPage(
        state,
        TranscriptPage(
          meetingId: state.pathParameters['id'] ?? '',
          initialMeeting: state.extra is Meeting ? state.extra! as Meeting : null,
        ),
      ),
    ),
    if (kDebugMode) ...<RouteBase>[
      GoRoute(
        path: '/gallery',
        name: 'gallery',
        pageBuilder: (BuildContext context, GoRouterState state) => _transitionPage(
          state,
          GalleryScreen(onOpen: (String id) => context.push('/gallery/$id')),
        ),
      ),
      GoRoute(
        path: '/gallery/:id',
        name: 'galleryScreen',
        pageBuilder: (BuildContext context, GoRouterState state) => _transitionPage(
          state,
          GalleryScreenHost(
            screenId: state.pathParameters['id'] ?? 's01',
            onExit: () => context.canPop()
                ? context.pop()
                : context.go('/gallery'),
            onOpenScreen: (String id) => context.push('/gallery/$id'),
          ),
        ),
      ),
    ],
  ],
);

/// 页面过渡时长（全站统一）。
const Duration kPageTransitionDuration = Duration(milliseconds: 220);

/// 统一的淡入 + 轻微上移过渡页（告别硬切导致的闪屏）。
///
/// 所有页面都包一层 [AppBackHandler]：系统返回键由它统一接管
/// （详情页退回上一步 → 首页双击返回才退出）。
CustomTransitionPage<void> _transitionPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: AppBackHandler(child: child),
      transitionDuration: kPageTransitionDuration,
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final CurvedAnimation curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
    );

/// 系统返回键统一接管。
///
/// 行为（对齐用户要求「返回=回到上一步」）：
/// 1. 压栈页 → 在 pop 回调里**实时** `context.canPop()` 判定为 true →
///    主动 `context.pop()`（反向过渡播放，回到上一页）；
/// 2. 根页（无栈可弹）：非首页 → 回首页兜底（深链冷启动时转写页先退回纪要页）；
/// 3. 首页 → 第一次提示「再按一次退出应用」，窗口期内再次返回才退出。
///
/// 为什么 `canPop` 恒 false、在回调里实时判定：`canPop` 若在 build 时求值，
/// 被覆盖的根页可能因 Riverpod 重建拿到陈旧的 true，返回键会既不 pop 也不退出。
/// 恒 false + 实时判定让每次返回都拿到当下真实的栈状态。
class AppBackHandler extends ConsumerStatefulWidget {
  /// 构造返回接管层。
  const AppBackHandler({super.key, required this.child});

  /// 页面内容。
  final Widget child;

  @override
  ConsumerState<AppBackHandler> createState() => _AppBackHandlerState();
}

class _AppBackHandlerState extends ConsumerState<AppBackHandler> {
  /// 两次返回视为「退出」的时间窗口。
  static const Duration _exitWindow = Duration(milliseconds: 2200);

  DateTime? _lastBackAt;

  void _handleBack() {
    // 实时判定：压栈页 → 原生 pop（返回上一步）。
    if (context.canPop()) {
      context.pop();
      return;
    }
    final String current = GoRouterState.of(context).matchedLocation;
    if (current != '/' && current.isNotEmpty) {
      // 深链兜底：转写页直接冷启动时至少退回它的纪要页，而不是跳首页。
      final RegExpMatch? transcript =
          RegExp(r'^/meeting/([^/]+)/transcript').firstMatch(current);
      appRouter.go(transcript != null ? '/meeting/${transcript.group(1)}' : '/');
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastBackAt != null && now.difference(_lastBackAt!) <= _exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    ref.read(toastProvider.notifier).show('再按一次退出应用', tone: ToastTone.info);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }
}
