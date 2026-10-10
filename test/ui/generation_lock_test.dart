/// 首页待机 / 收尾按钮的组件行为回归。
///
/// 历史（Bug 2 回归）：「结束并生成 → 按钮 loading → 跳详情页」的 UI 表现。
/// 2026-10-10 起生成锁（SessionGenerationController）已整体移除——终稿 / 纪要
/// 全部后台化（finalize_poller 自动触发纪要），首页不再因上一段生成而禁录，
/// 锁状态机的测试随之删除；本文件仅保留与锁无关的组件行为测试。
///
/// 说明：`flutter test` 环境没有麦克风硬件，完整录音链路用假 [MicSource]
/// 驱动（见 recorder_mic_test.dart）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/home_idle_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/record_hero_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/recording_controls.dart';

/// Hero 卡内的麦克风图标（TabBar 也有同款图标，必须限定范围）。
Finder _heroMic() => find.descendant(
      of: find.byType(RecordHeroCard),
      matching: find.byIcon(Icons.mic_rounded),
    );

/// Hero 卡内的 spinner。
Finder _heroSpinner() => find.descendant(
      of: find.byType(RecordHeroCard),
      matching: find.byType(CircularProgressIndicator),
    );

void main() {
  group('首页待机屏 busy 表现', () {
    testWidgets('busy 时麦克风变成 spinner 且点击无效', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: HomeIdleScreen(
              greeting: '早上好，苏木',
              userName: '苏木',
              heroStatusText: '处理中',
              heroStatusTail: '今日已记录 42 分钟',
              modes: const <String>['会议', '访谈', '灵感'],
              selectedMode: 0,
              recentItems: const <HistoryItemView>[],
              onMicTap: () => taps++,
              onModeChanged: (int _) {},
              onViewAll: () {},
              onTabTap: (int _) {},
              busy: true,
              busyHint: '正在启动录音…',
            ),
          ),
        ),
      );

      expect(find.text('正在启动录音…'), findsOneWidget);
      expect(_heroMic(), findsNothing);
      expect(_heroSpinner(), findsOneWidget);

      await tester.tap(_heroSpinner().first);
      await tester.pump();
      expect(taps, 0, reason: 'busy 期间点击麦克风不应触发录音');
    });

    testWidgets('非 busy 时麦克风可点', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: HomeIdleScreen(
              greeting: '早上好，苏木',
              userName: '苏木',
              heroStatusText: '待机中',
              heroStatusTail: '今日已记录 42 分钟',
              modes: const <String>['会议', '访谈', '灵感'],
              selectedMode: 0,
              recentItems: const <HistoryItemView>[],
              onMicTap: () => taps++,
              onModeChanged: (int _) {},
              onViewAll: () {},
              onTabTap: (int _) {},
            ),
          ),
        ),
      );

      await tester.tap(_heroMic());
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('结束并生成按钮 loading', () {
    testWidgets('stopping：主按钮转圈、文案切换、三键禁用', (WidgetTester tester) async {
      int stops = 0;
      int pauses = 0;
      int marks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: RecordingControls(
              paused: false,
              stopping: true,
              onPauseToggle: () => pauses++,
              onStop: () => stops++,
              onBookmark: () => marks++,
            ),
          ),
        ),
      );

      expect(find.text('正在生成…'), findsOneWidget);
      expect(find.text('结束并生成'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('正在生成…'));
      await tester.pump();
      expect(stops, 0, reason: '收尾中不应重复触发');
      // 两侧按钮也应禁用（图标存在但点击无效）。
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pump();
      expect(pauses, 0);
      expect(marks, 0);
    });

    testWidgets('非 stopping：可点击并回传', (WidgetTester tester) async {
      int stops = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: RecordingControls(
              paused: false,
              onPauseToggle: () {},
              onStop: () => stops++,
              onBookmark: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('结束并生成'));
      await tester.pump();
      expect(stops, 1);
    });
  });
}
