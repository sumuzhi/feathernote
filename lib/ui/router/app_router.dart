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
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: 'record',
      builder: (BuildContext context, GoRouterState state) => const HomePage(),
    ),
    GoRoute(
      path: '/history',
      name: 'history',
      builder: (BuildContext context, GoRouterState state) => const HistoryPage(),
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (BuildContext context, GoRouterState state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/meeting/:id',
      name: 'meeting',
      builder: (BuildContext context, GoRouterState state) =>
          MeetingPage(meetingId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/meeting/:id/transcript',
      name: 'transcript',
      // `extra` 携带来源页已加载的 [Meeting]，供转写页首帧直接渲染（消除闪烁）。
      builder: (BuildContext context, GoRouterState state) => TranscriptPage(
        meetingId: state.pathParameters['id'] ?? '',
        initialMeeting: state.extra is Meeting ? state.extra! as Meeting : null,
      ),
    ),
    if (kDebugMode) ...<RouteBase>[
      GoRoute(
        path: '/gallery',
        name: 'gallery',
        builder: (BuildContext context, GoRouterState state) => GalleryScreen(
          onOpen: (String id) => context.go('/gallery/$id'),
        ),
      ),
      GoRoute(
        path: '/gallery/:id',
        name: 'galleryScreen',
        builder: (BuildContext context, GoRouterState state) => GalleryScreenHost(
          screenId: state.pathParameters['id'] ?? 's01',
          onExit: () => context.go('/gallery'),
          onOpenScreen: (String id) => context.go('/gallery/$id'),
        ),
      ),
    ],
  ],
);
