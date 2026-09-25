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
import 'package:go_router/go_router.dart';

import '../../domain/meeting.dart';
import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/meeting_page.dart';
import '../pages/profile_page.dart';
import '../pages/transcript_page.dart';
import '../screens/gallery_screen.dart';

/// 全局路由。
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
          GalleryScreen(onOpen: (String id) => context.go('/gallery/$id')),
        ),
      ),
      GoRoute(
        path: '/gallery/:id',
        name: 'galleryScreen',
        pageBuilder: (BuildContext context, GoRouterState state) => _transitionPage(
          state,
          GalleryScreenHost(
            screenId: state.pathParameters['id'] ?? 's01',
            onExit: () => context.go('/gallery'),
            onOpenScreen: (String id) => context.go('/gallery/$id'),
          ),
        ),
      ),
    ],
  ],
);

/// 页面过渡时长（全站统一）。
const Duration kPageTransitionDuration = Duration(milliseconds: 220);

/// 统一的淡入 + 轻微上移过渡页（告别硬切导致的闪屏）。
CustomTransitionPage<void> _transitionPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
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
