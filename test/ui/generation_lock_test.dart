/// Bug 2 回归：结束并生成 → 按钮 loading → 跳详情页 → 生成期首页禁用 → 结束恢复。
///
/// 说明：`flutter test` 环境没有麦克风硬件，因此「录音 → 停止」的完整链路用
/// 假 [MicSource] 驱动（见 recorder_mic_test.dart）；本文件覆盖状态机与 UI 表现。
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/screens/home_idle_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/record_hero_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/recording_controls.dart';

MeetingSummary _summary(
  String id, {
  required bool hasMinutes,
  FinalizeStatus finalize = FinalizeStatus.none,
}) =>
    MeetingSummary(
      id: id,
      title: '会议 $id',
      createdAt: DateTime(2026, 9, 24, 10),
      durationMs: 60000,
      speakerCount: 2,
      status: MeetingStatus.stopped,
      finalizeStatus: finalize,
      hasMinutes: hasMinutes,
      minutesPartial: false,
    );

ProviderContainer _container(Stream<List<MeetingSummary>> meetings) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      meetingsProvider.overrideWith((Ref ref) => meetings),
    ],
  );
  addTearDown(container.dispose);
  // 关键：镜像生产接线 —— 首页 `ref.watch(generationInProgressProvider)` 使该
  // provider 处于「被监听」状态。Riverpod 3 会暂停「无监听者」的 provider 及其
  // 依赖（含本控制器对 meetingsProvider 的 `ref.listen`）；若不保持监听，兜底
  // 回调不会触发（实测：无人 watch 时 state 恒为 'm1'；有人 watch 时按时解锁）。
  container.listen<String?>(generationInProgressProvider, (_, _) {});
  return container;
}

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

/// 首页待机屏宿主：把「生成锁」翻译成 busy，模拟 HomePage 的接线。
class _HomeHarness extends ConsumerWidget {
  const _HomeHarness({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool busy = ref.watch(generationInProgressProvider) != null;
    return HomeIdleScreen(
      greeting: '早上好，苏木',
      userName: '苏木',
      heroStatusText: busy ? '处理中' : '待机中',
      heroStatusTail: '今日已记录 42 分钟',
      modes: const <String>['会议', '访谈', '灵感'],
      selectedMode: 0,
      recentItems: const <HistoryItemView>[],
      onMicTap: onTap,
      onModeChanged: (int _) {},
      onViewAll: () {},
      onTabTap: (int _) {},
      busy: busy,
      busyHint: busy ? '上一段正在生成纪要…' : null,
    );
  }
}

void main() {
  group('SessionGenerationController 状态机', () {
    test('begin 上锁；end 只对匹配的会议生效', () {
      final ProviderContainer container =
          _container(const Stream<List<MeetingSummary>>.empty());
      final SessionGenerationController notifier =
          container.read(generationInProgressProvider.notifier);

      expect(container.read(generationInProgressProvider), isNull);
      notifier.begin('m1');
      expect(container.read(generationInProgressProvider), 'm1');

      // 非本会话的 end 必须被忽略（否则老会议会误解锁）。
      notifier.end('m2');
      expect(container.read(generationInProgressProvider), 'm1');

      notifier.end('m1');
      expect(container.read(generationInProgressProvider), isNull);

      // 幂等：再 end 不报错。
      notifier.end();
      expect(container.read(generationInProgressProvider), isNull);
    });

    test('兜底一：被跟踪会议仍在生成 → 保持上锁', () async {
      final StreamController<List<MeetingSummary>> controller =
          StreamController<List<MeetingSummary>>.broadcast();
      addTearDown(controller.close);
      final ProviderContainer container = _container(controller.stream);
      final SessionGenerationController notifier =
          container.read(generationInProgressProvider.notifier);
      notifier.begin('m1');

      controller.add(<MeetingSummary>[_summary('m1', hasMinutes: false)]);
      await pumpEventQueue();
      expect(container.read(generationInProgressProvider), 'm1');
    });

    test('兜底二：会议已有纪要且终稿不再 pending → 自动解锁', () async {
      final StreamController<List<MeetingSummary>> controller =
          StreamController<List<MeetingSummary>>.broadcast();
      addTearDown(controller.close);
      final ProviderContainer container = _container(controller.stream);
      final SessionGenerationController notifier =
          container.read(generationInProgressProvider.notifier);
      notifier.begin('m1');

      controller.add(<MeetingSummary>[
        _summary('m1', hasMinutes: true, finalize: FinalizeStatus.done),
      ]);
      await pumpEventQueue();
      expect(container.read(generationInProgressProvider), isNull);
    });

    test('兜底三：终稿仍 pending 时不解锁；会议被删除则解锁', () async {
      final StreamController<List<MeetingSummary>> controller =
          StreamController<List<MeetingSummary>>.broadcast();
      addTearDown(controller.close);
      final ProviderContainer container = _container(controller.stream);
      final SessionGenerationController notifier =
          container.read(generationInProgressProvider.notifier);
      notifier.begin('m1');

      controller.add(<MeetingSummary>[
        _summary('m1', hasMinutes: true, finalize: FinalizeStatus.pending),
      ]);
      await pumpEventQueue();
      expect(container.read(generationInProgressProvider), 'm1',
          reason: '终稿仍在处理中，应继续禁用开始录音');

      controller.add(const <MeetingSummary>[]);
      await pumpEventQueue();
      expect(container.read(generationInProgressProvider), isNull);
    });

    test('兜底四：超时（kGenerationLockMax）强制解锁，不永久锁死', () {
      fakeAsync((FakeAsync async) {
        final ProviderContainer container =
            ProviderContainer(
          overrides: [
            meetingsProvider.overrideWith(
              (Ref ref) => const Stream<List<MeetingSummary>>.empty(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(generationInProgressProvider.notifier).begin('m1');
        expect(container.read(generationInProgressProvider), 'm1');

        async.elapse(kGenerationLockMax + const Duration(seconds: 1));
        expect(container.read(generationInProgressProvider), isNull);
      });
    });
  });

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
              busyHint: '上一段正在生成纪要…',
            ),
          ),
        ),
      );

      expect(find.text('上一段正在生成纪要…'), findsOneWidget);
      expect(_heroMic(), findsNothing);
      expect(_heroSpinner(), findsOneWidget);

      await tester.tap(_heroSpinner().first);
      await tester.pump();
      expect(taps, 0, reason: '生成期间点击麦克风不应触发录音');
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

  testWidgets('状态迁移：begin 禁用 → end 恢复可点', (WidgetTester tester) async {
    final StreamController<List<MeetingSummary>> controller =
        StreamController<List<MeetingSummary>>.broadcast();
    addTearDown(controller.close);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        meetingsProvider.overrideWith((Ref ref) => controller.stream),
      ],
    );
    addTearDown(container.dispose);

    int taps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: _HomeHarness(onTap: () => taps++),
        ),
      ),
    );

    // 1) 初始可用。
    await tester.tap(_heroMic());
    await tester.pump();
    expect(taps, 1);

    // 2) 本会话开始生成 → 首页开始录音禁用 + 可见原因。
    container.read(generationInProgressProvider.notifier).begin('m1');
    await tester.pump();
    expect(find.text('上一段正在生成纪要…'), findsOneWidget);
    expect(_heroMic(), findsNothing);

    // 3) 生成结束 → 自动恢复可用。
    container.read(generationInProgressProvider.notifier).end('m1');
    await tester.pump();
    expect(find.text('上一段正在生成纪要…'), findsNothing);
    expect(_heroMic(), findsOneWidget);
    await tester.tap(_heroMic());
    await tester.pump();
    expect(taps, 2);
  });
}
