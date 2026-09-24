/// 路由表。
///
/// - 三个 Tab 页在 [ShellRoute] 内（底部 TabBar 常驻）：`/`、`/history`、`/profile`；
/// - 纪要页与完整转写页是**压栈页**（设计稿 11/07 没有 TabBar）。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/meeting_page.dart';
import '../pages/profile_page.dart';
import '../pages/transcript_page.dart';
import '../shell/app_shell.dart';

/// 全局路由。
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) =>
          AppShell(location: state.uri.path, child: child),
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
      ],
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
      builder: (BuildContext context, GoRouterState state) =>
          TranscriptPage(meetingId: state.pathParameters['id'] ?? ''),
    ),
  ],
);
