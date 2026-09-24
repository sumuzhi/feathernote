import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/demo/demo_data.dart';
import 'package:smart_minutes_flutter/ui/screens/gallery_screen.dart';
import 'package:smart_minutes_flutter/ui/screens/screen_frame.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/theme/speaker_palette.dart';
import 'package:smart_minutes_flutter/ui/utils/speaker_view.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_badge.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_button.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_switch.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_tab_bar.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_toast.dart';
import 'package:smart_minutes_flutter/ui/widgets/empty_state.dart';
import 'package:smart_minutes_flutter/ui/widgets/filter_chips.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/hit_bar.dart';
import 'package:smart_minutes_flutter/ui/widgets/meeting_info_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/minutes_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/recording_controls.dart';
import 'package:smart_minutes_flutter/ui/widgets/segmented_control.dart';
import 'package:smart_minutes_flutter/ui/widgets/speaker_chips.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';
import 'package:smart_minutes_flutter/ui/widgets/waveform.dart';

/// 把被测组件放进最小可渲染环境（主题 + Scaffold + 可滚动）。
Widget _host(Widget child, {bool scroll = true}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: scroll ? SingleChildScrollView(child: child) : child,
    ),
  );
}

/// [ScreenFrame] 用了 `Positioned`，必须放在 `Stack` 里。
Widget _stackHost(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Stack(children: <Widget>[child])),
  );
}

void main() {
  group('设计 token（对齐 HTML :root）', () {
    test('修正后的 5 处值与 8 组说话人色板', () {
      expect(AppColors.line, const Color(0xFFF1E7DC));
      expect(AppColors.orangeDeep, const Color(0xFFE8662A));
      expect(AppColors.body, const Color(0xFF4A3A30));
      expect(AppColors.faint, const Color(0xFFB8A899));
      expect(AppColors.orangeWash, const Color(0xFFFBE9DB));
      expect(AppShadow.card.first.blurRadius, 18);
      expect(AppShadow.card.first.offset, const Offset(0, 6));
      expect(AppShadow.card.first.color, const Color(0x0D3A2A20));
      expect(AppRadius.card, 24);
      expect(AppRadius.card2, 20);
      expect(kSpeakerPalette.length, 8);
      expect(speakerColor(8), const Color(0xFFA79A8E));
      expect(speakerSoftColor(1), const Color(0xFFFDEEE2));
    });
  });

  group('AppBadge / AppTag', () {
    testWidgets('渲染文案并可按语气取色', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AppBadge(text: '已总结')));
      expect(find.text('已总结'), findsOneWidget);

      await tester.pumpWidget(
        _host(const AppBadge(text: '已完成', tone: AppBadgeTone.done)),
      );
      final Container container = tester.widget<Container>(
        find.ancestor(of: find.text('已完成'), matching: find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color, AppColors.greenBg);
    });

    testWidgets('标签支持 chip 底色（屏 11「内容较长」）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AppTag(text: '内容较长', wash: true)));
      final Container container = tester.widget<Container>(
        find.ancestor(of: find.text('内容较长'), matching: find.byType(Container)).first,
      );
      expect((container.decoration! as BoxDecoration).color, AppColors.orangeWash);
    });
  });

  group('AppSegmentedControl', () {
    testWidgets('点击切换并回调下标', (WidgetTester tester) async {
      int current = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => _host(
            AppSegmentedControl(
              labels: const <String>['会议', '访谈', '灵感'],
              selectedIndex: current,
              onChanged: (int index) => setState(() => current = index),
            ),
          ),
        ),
      );
      expect(find.text('会议'), findsOneWidget);
      await tester.tap(find.text('访谈'));
      await tester.pumpAndSettle();
      expect(current, 1);
    });
  });

  group('Waveform', () {
    testWidgets('渲染 44 根柱（对齐 HTML n=44）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const Waveform(), scroll: false));
      expect(find.byType(Opacity), findsNWidgets(kWaveformBarCount));
      // 柱高函数与 HTML buildWave 一致：中间高两侧低。
      expect(waveformBarHeight(22) > waveformBarHeight(0), isTrue);
      expect(waveformBarHeight(0) >= 8, isTrue);
      expect(waveformBarHeight(22) <= 78, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('减少动效时不起 ticker，柱体静态', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Waveform(),
          ),
          scroll: false,
        ),
      );
      expect(find.byType(Opacity), findsNWidgets(kWaveformBarCount));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('SpeakerChip / SpeakerAvatar', () {
    testWidgets('彩色 chip 按序号取色，灰色 chip 用于「识别中」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: <Widget>[
              SpeakerChip(view: SpeakerChipView(ordinal: 1, label: '说话人 1')),
              SpeakerChip(
                view: SpeakerChipView(ordinal: 8, label: '说话人 8 · 识别中', gray: true),
              ),
              SpeakerAvatar(ordinal: 3),
            ],
          ),
        ),
      );
      expect(find.text('说话人 1'), findsOneWidget);
      expect(find.text('说话人 8 · 识别中'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('TranscriptTile', () {
    testWidgets('渲染说话人、时间与正文', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const TranscriptTile(
            item: TranscriptItemView(
              ordinal: 1,
              speakerLabel: '说话人 1',
              timeLabel: '00:12',
              text: '大家下午好，今天我们主要讨论第三季度的产品规划。',
            ),
          ),
        ),
      );
      expect(find.text('说话人 1 · 00:12', findRichText: true), findsOneWidget);
      expect(find.textContaining('第三季度的产品规划'), findsOneWidget);
    });

    testWidgets('待上传态半透明，命中态带高亮底与「展开这段」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const TranscriptTile(
            item: TranscriptItemView(
              ordinal: 2,
              speakerLabel: '说话人 2',
              timeLabel: '待上传',
              text: '这一段已缓存在本地。',
              pending: true,
            ),
          ),
        ),
      );
      expect(find.text('说话人 2 · 待上传', findRichText: true), findsOneWidget);
      final Opacity opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 0.55);

      bool expanded = false;
      await tester.pumpWidget(
        _host(
          TranscriptTile(
            item: const TranscriptItemView(
              ordinal: 1,
              speakerLabel: '说话人 1',
              timeLabel: '03:05',
              text: '激活率这边我让数据团队重新拉了一版口径。',
              highlight: true,
              expandNote: '展开这段 · 1,860 字',
            ),
            onExpand: () => expanded = true,
          ),
        ),
      );
      expect(find.text('展开这段 · 1,860 字'), findsOneWidget);
      await tester.tap(find.text('展开这段 · 1,860 字'));
      expect(expanded, isTrue);
    });
  });

  group('speakerViewFor', () {
    test('优先命中说话人表，否则由 spk_N 推导', () {
      const List<Speaker> speakers = <Speaker>[
        Speaker(
          meetingId: 'm1',
          speakerId: 'spk_2',
          name: '张老师',
          colorIndex: 1,
          firstSeenMs: 0,
        ),
      ];
      final SpeakerView hit = speakerViewFor(speakerId: 'spk_2', speakers: speakers);
      expect(hit.name, '张老师');
      expect(hit.ordinal, 1);

      final SpeakerView derived = speakerViewFor(speakerId: 'spk_3', speakers: speakers);
      expect(derived.name, '说话人 3');

      final SpeakerView pending = speakerViewFor(
        speakerId: kPendingSpeakerId,
        speakers: speakers,
      );
      expect(pending.isPending, isTrue);
    });
  });

  group('HistoryCard', () {
    testWidgets('展示标题、单行描述、元信息与徽标', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _host(
          HistoryCard(
            item: HistoryItemView(
              title: 'Q3 产品规划评审',
              description: '明确激活率目标上调至 35%，渠道合作 8 月底前完成落地。',
              meta: '32 分钟 · 今天 09:12 · 3 人',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('Q3 产品规划评审'), findsOneWidget);
      expect(find.textContaining('明确激活率目标上调至 35%'), findsOneWidget);
      expect(find.text('32 分钟 · 今天 09:12 · 3 人'), findsOneWidget);
      expect(find.text('已总结'), findsOneWidget);
      await tester.tap(find.text('Q3 产品规划评审'));
      expect(tapped, isTrue);
    });

    testWidgets('已完成徽标与截断卡（屏 09）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const HistoryCard(
            item: HistoryItemView(
              title: '设计评审 · 激活链路改版',
              description: '确认引导页压缩至两步，新增一键跳过入口。',
              meta: '54 分钟 · 14:05 · 4 人',
              badge: HistoryBadge.done,
              cut: true,
              dimBadge: true,
            ),
          ),
        ),
      );
      expect(find.text('已完成'), findsOneWidget);
      final HistoryItemView view = tester
          .widget<HistoryCard>(find.byType(HistoryCard))
          .item;
      expect(view.cut, isTrue);
    });
  });

  group('MinutesCard', () {
    testWidgets('常规纪要：标签、摘要、分节与「查看完整转写」独立行', (WidgetTester tester) async {
      bool opened = false;
      await tester.pumpWidget(
        _host(
          MinutesCard(
            view: MinutesView(
              title: '✦ AI 结构化纪要',
              modelTag: 'qwen3.7-plus',
              abstractText: '本次会议围绕 Q3 产品规划展开，核心共识是激活率目标上调至 35%。',
              sections: const <MinutesSectionView>[
                MinutesSectionView(
                  title: '重要决策',
                  items: <String>['激活率目标上调至 35%。'],
                ),
              ],
              transcriptChars: '1,860 字 ›',
              onOpenTranscript: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('✦ AI 结构化纪要'), findsOneWidget);
      expect(find.text('qwen3.7-plus'), findsOneWidget);
      expect(find.text('重要决策'), findsOneWidget);
      expect(find.text('查看完整转写'), findsOneWidget);
      expect(find.text('1,860 字 ›'), findsOneWidget);
      await tester.tap(find.text('查看完整转写'));
      expect(opened, isTrue);
    });

    testWidgets('超长纪要：内容较长标签 + 展开全文 + 查看全部 N 条', (WidgetTester tester) async {
      bool expanded = false;
      int? moreIndex;
      await tester.pumpWidget(
        _host(
          MinutesCard(
            view: MinutesView(
              title: '✦ AI 结构化纪要',
              modelTag: 'qwen3.7-plus',
              longTag: true,
              abstractText: '本次会议围绕 Q3 产品规划展开…',
              expandNote: '展开全文 · 摘要约 1,240 字',
              sections: const <MinutesSectionView>[
                MinutesSectionView(
                  title: '重要决策 · 共 8 条',
                  items: <String>['激活率目标上调至 35%。'],
                  moreLabel: '查看全部 8 条决策',
                ),
              ],
              transcriptChars: '1,860 字 ›',
              onExpandAbstract: () => expanded = true,
              onMore: (int index) => moreIndex = index,
            ),
          ),
        ),
      );
      expect(find.text('内容较长'), findsOneWidget);
      expect(find.text('重要决策 · 共 8 条'), findsOneWidget);
      expect(find.text('查看全部 8 条决策'), findsOneWidget);
      await tester.tap(find.text('展开全文 · 摘要约 1,240 字'));
      expect(expanded, isTrue);
      await tester.tap(find.text('查看全部 8 条决策'));
      expect(moreIndex, 0);
    });
  });

  group('AppSwitch', () {
    testWidgets('点击切换并回调', (WidgetTester tester) async {
      bool value = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => _host(
            AppSwitch(
              value: value,
              onChanged: (bool next) => setState(() => value = next),
            ),
            scroll: false,
          ),
        ),
      );
      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });
  });

  group('FilterChipRow', () {
    testWidgets('渲染全部项并在点击时回传下标', (WidgetTester tester) async {
      int? tapped;
      await tester.pumpWidget(
        _host(
          FilterChipRow(
            items: const <FilterChipView>[
              FilterChipView(label: '全部', selected: true),
              FilterChipView(label: '今天'),
              FilterChipView(label: '本周'),
              FilterChipView(label: '已总结'),
            ],
            onTap: (int index) => tapped = index,
          ),
        ),
      );
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('已总结'), findsOneWidget);
      await tester.tap(find.text('本周'));
      expect(tapped, 2);
    });
  });

  group('HitBar（屏 12）', () {
    testWidgets('展示命中数、序号并响应上下与关闭', (WidgetTester tester) async {
      int prev = 0;
      int next = 0;
      int close = 0;
      await tester.pumpWidget(
        _host(
          HitBar(
            total: 12,
            current: 3,
            keyword: '激活',
            onPrev: () => prev++,
            onNext: () => next++,
            onClose: () => close++,
          ),
        ),
      );
      expect(find.text('找到 12 处「激活」'), findsOneWidget);
      expect(find.text('3 / 12'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_less_rounded));
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(prev, 1);
      expect(next, 1);
      expect(close, 1);
    });
  });

  group('ScreenFrame + AppTabBar', () {
    testWidgets('三个 Tab 常驻并回传下标', (WidgetTester tester) async {
      int? tapped;
      await tester.pumpWidget(
        _stackHost(
          ScreenFrame(
            tabIndex: 1,
            onTabTap: (int index) => tapped = index,
            body: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('录音'), findsOneWidget);
      expect(find.text('历史'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      await tester.tap(find.text('我的'));
      expect(tapped, 2);
    });

    testWidgets('底部 CTA 与状态栏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _stackHost(
          const ScreenFrame(
            bottomCta: AppPillButton(label: '导出纪要', onTap: _noop),
            body: SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('9:41'), findsOneWidget);
      expect(find.text('导出纪要'), findsOneWidget);
      expect(find.byType(AppTabBar), findsNothing);
    });
  });

  group('AppEmptyState / AppToast', () {
    testWidgets('空态可带 CTA', (WidgetTester tester) async {
      bool acted = false;
      await tester.pumpWidget(
        _host(
          AppEmptyState(
            icon: Icons.mic_rounded,
            title: '还没有会议记录',
            description: '点下方按钮开始，第一段录音只需 3 秒上手',
            cta: AppEmptyCtaButton(
              label: '开始第一次录音',
              onTap: () => acted = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始第一次录音'));
      expect(acted, isTrue);
    });

    testWidgets('Toast 从顶部滑入并在清除后隐藏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const AppToastOverlay(
            message: ToastMessage(text: '网络连接中断', tone: ToastTone.warning),
            child: SizedBox.expand(),
          ),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络连接中断'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          const AppToastOverlay(message: null, child: SizedBox.expand()),
          scroll: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络连接中断'), findsNothing);
    });

    testWidgets('断线 Toast 带副文案与重试按钮（屏 06）', (WidgetTester tester) async {
      bool retried = false;
      await tester.pumpWidget(
        _host(
          AppActionToast(
            title: '网络连接中断',
            subtitle: '正在本地缓存音频，恢复后自动续传',
            actionLabel: '重试',
            onAction: () => retried = true,
          ),
          scroll: false,
        ),
      );
      expect(find.text('正在本地缓存音频，恢复后自动续传'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });
  });

  group('RecordingControls（屏 02 控制区）', () {
    testWidgets('三键回调：暂停 / 结束并生成 / 标记', (WidgetTester tester) async {
      int pause = 0;
      int stop = 0;
      int bookmark = 0;
      await tester.pumpWidget(
        _host(
          RecordingControls(
            paused: false,
            onPauseToggle: () => pause++,
            onStop: () => stop++,
            onBookmark: () => bookmark++,
          ),
          scroll: false,
        ),
      );
      expect(find.text('结束并生成'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.text('结束并生成'));
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      expect(pause, 1);
      expect(stop, 1);
      expect(bookmark, 1);
    });

    testWidgets('暂停后切换为「继续」图标', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const RecordingControls(
            paused: true,
            onPauseToggle: _noop,
            onStop: _noop,
            onBookmark: _noop,
          ),
          scroll: false,
        ),
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('MeetingInfoCard', () {
    testWidgets('展示标题、徽标与元信息', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const MeetingInfoCard(
            title: 'Q3 产品规划评审',
            meta: '3 小时 12 分钟 · 8 位说话人 · 今天 09:12',
          ),
        ),
      );
      expect(find.text('Q3 产品规划评审'), findsOneWidget);
      expect(find.text('3 小时 12 分钟 · 8 位说话人 · 今天 09:12'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
    });
  });

  group('演示数据（与 HTML TRANSCRIPT / HIST / HIST09 对齐）', () {
    test('TRANSCRIPT 7 条、HIST 4 条、HIST09 分两组各 2 条', () {
      expect(kDemoTranscript.length, 7);
      expect(kDemoTranscript.first.time, '00:12');
      expect(kDemoTranscript.last.time, '15:02');
      expect(kDemoTranscript.first.seconds, 12);
      expect(kDemoTranscript.last.seconds, 15 * 60 + 2);

      expect(demoHistoryViews().length, 4);
      expect(demoHistoryViews().first.title, 'Q3 产品规划评审');
      expect(demoHistoryViews().last.badge, HistoryBadge.done);

      final List<DemoHistoryGroup> groups = demoLongHistoryGroups();
      expect(groups.length, 2);
      expect(groups.first.day, '今天');
      expect(groups.last.day, '昨天');
      expect(groups.last.items.last.cut, isTrue);

      expect(demoShortMinutesView().modelTag, 'qwen3.7-plus');
      expect(demoLongMinutesView().longTag, isTrue);
      expect(demoLongMinutesView().expandNote, '展开全文 · 摘要约 1,240 字');
      expect(demoLongMinutesView(expanded: true).expandNote, '收起');
    });
  });

  group('屏幕目录（13 屏）', () {
    test('目录包含 s01–s13', () {
      expect(kGalleryEntries.length, 13);
      expect(kGalleryEntries.first.id, 's01');
      expect(kGalleryEntries.last.id, 's13');
      final Set<String> ids =
          kGalleryEntries.map((GalleryEntry e) => e.id).toSet();
      expect(ids.length, 13);
    });

    testWidgets('目录页列出全部条目并回传屏号', (WidgetTester tester) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: GalleryScreen(onOpen: (String id) => opened = id),
        ),
      );
      expect(find.text('待机态 · 首页'), findsOneWidget);
      await tester.tap(find.text('待机态 · 首页'));
      expect(opened, 's01');
    });
  });
}

void _noop() {}
