import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/recording_mode.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/shell/app_shell.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/utils/speaker_view.dart';
import 'package:smart_minutes_flutter/ui/widgets/action_row.dart';
import 'package:smart_minutes_flutter/ui/widgets/ai_summary_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_badge.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_toast.dart';
import 'package:smart_minutes_flutter/ui/widgets/empty_state.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/meeting_info_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/segmented_control.dart';
import 'package:smart_minutes_flutter/ui/widgets/speaker_chips.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/waveform.dart';

/// 把被测组件放进最小可渲染环境（主题 + Scaffold + 可滚动）。
Widget _host(Widget child, {bool scroll = false}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: scroll
          ? SingleChildScrollView(child: child)
          : Center(child: child),
    ),
  );
}

const String _minutesMarkdown = '''
# 核心观点
本次会议围绕 Q3 产品规划展开，共 8 位发言人参与，核心共识是把新用户激活率目标定为 35%。

# 内容总结
## 一、重要决策
1. Q3 激活率目标从 30% 上调至 35%，采用新统计口径。
2. 渠道合作协议由商务团队在 8 月底前签署完成。
3. 运营排期提前两周。

## 二、讨论要点
- 激活率按新口径重算后实际完成 82%。
- 用户访谈反馈引导页过长。
''';

MeetingSummary _summary({
  bool hasMinutes = true,
  String title = 'Q3 产品规划评审',
  String excerpt = '明确激活率目标上调至 35%，渠道合作 8 月底前完成落地。',
}) {
  return MeetingSummary(
    id: 'm1',
    title: title,
    createdAt: DateTime(2026, 9, 24, 9, 12),
    durationMs: 32 * 60000,
    speakerCount: 3,
    status: MeetingStatus.minutesReady,
    finalizeStatus: FinalizeStatus.done,
    hasMinutes: hasMinutes,
    minutesPartial: false,
    minutesExcerpt: excerpt,
  );
}

void main() {
  group('AppBadge', () {
    testWidgets('渲染文案并可按语气取色', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const AppBadge(label: '已总结')),
      );
      expect(find.text('已总结'), findsOneWidget);

      await tester.pumpWidget(
        _host(const AppBadge(label: '已完成', tone: BadgeTone.green)),
      );
      final Container container = tester.widget<Container>(
        find.ancestor(of: find.text('已完成'), matching: find.byType(Container)).first,
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.badgeDoneBg);
    });
  });

  group('SegmentedControl', () {
    testWidgets('点击切换模式并回调', (WidgetTester tester) async {
      RecordingMode current = RecordingMode.meeting;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => _host(
            SegmentedControl<RecordingMode>(
              options: const <SegmentOption<RecordingMode>>[
                SegmentOption<RecordingMode>(value: RecordingMode.meeting, label: '会议'),
                SegmentOption<RecordingMode>(value: RecordingMode.interview, label: '访谈'),
                SegmentOption<RecordingMode>(value: RecordingMode.inspiration, label: '灵感'),
              ],
              value: current,
              onChanged: (RecordingMode value) => setState(() => current = value),
            ),
          ),
        ),
      );
      expect(find.text('会议'), findsOneWidget);
      await tester.tap(find.text('访谈'));
      await tester.pumpAndSettle();
      expect(current, RecordingMode.interview);
    });
  });

  group('Waveform', () {
    testWidgets('按音量渲染柱状且不足时左补零', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const Waveform(levels: <double>[0.2, 0.6, 1.0], barCount: 6),
        ),
      );
      expect(find.byType(AnimatedContainer), findsNWidgets(6));
    });

    testWidgets('关闭动画时退化为静态容器（respect reduced motion）', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Waveform(levels: <double>[0.4], barCount: 4),
          ),
        ),
      );
      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  group('SpeakerChips', () {
    testWidgets('展示全部项并回调选中', (WidgetTester tester) async {
      String? selected = 'spk_1';
      await tester.pumpWidget(
        _host(
          SpeakerChips(
            speakers: const <Speaker>[
              Speaker(
                meetingId: 'm1',
                speakerId: 'spk_1',
                name: '发言人1',
                colorIndex: 0,
                firstSeenMs: 0,
              ),
              Speaker(
                meetingId: 'm1',
                speakerId: 'spk_2',
                name: '发言人2',
                colorIndex: 1,
                firstSeenMs: 1000,
              ),
            ],
            showAll: true,
            selectedId: selected,
            onSelected: (String? id) => selected = id,
          ),
        ),
      );
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('发言人1'), findsOneWidget);
      await tester.tap(find.text('全部'));
      await tester.pump();
      expect(selected, isNull);
    });
  });

  group('TranscriptTile / TranscriptCard', () {
    testWidgets('渲染片段与「自动滚动」徽标，空态给出提示', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const TranscriptCard(segments: <TranscriptSegment>[]),
          scroll: true,
        ),
      );
      expect(find.text('实时转写'), findsOneWidget);
      expect(find.text('自动滚动'), findsOneWidget);
      expect(find.text('正在聆听，请开始说话…'), findsOneWidget);
    });

    testWidgets('片段按说话人着色并显示时间', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const TranscriptCard(
            segments: <TranscriptSegment>[
              TranscriptSegment(
                meetingId: 'm1',
                segmentId: 'seg_1',
                ordinal: 0,
                speakerId: 'spk_1',
                text: '大家下午好，今天主要讨论第三季度的产品规划。',
                startTime: 12000,
                endTime: 20000,
                confidence: 0.9,
                seqStart: 600,
                seqEnd: 999,
              ),
            ],
            speakers: <Speaker>[
              Speaker(
                meetingId: 'm1',
                speakerId: 'spk_1',
                name: '发言人1',
                colorIndex: 0,
                firstSeenMs: 0,
              ),
            ],
          ),
          scroll: true,
        ),
      );
      expect(find.text('发言人1'), findsOneWidget);
      expect(find.text('  ·  0:12'), findsOneWidget);
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
      expect(hit.colorIndex, 1);
      expect(hit.ordinal, 1);

      final SpeakerView derived = speakerViewFor(speakerId: 'spk_3', speakers: speakers);
      expect(derived.name, '说话人 3');
      expect(derived.colorIndex, 2);

      final SpeakerView pending = speakerViewFor(
        speakerId: kPendingSpeakerId,
        speakers: speakers,
      );
      expect(pending.isPending, isTrue);
      expect(pending.ordinal, 1);
    });
  });

  group('HistoryCard', () {
    testWidgets('展示标题、纪要预览、元信息与徽标', (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _host(
          HistoryCard(summary: _summary(), onTap: () => tapped = true, now: DateTime(2026, 9, 24, 20)),
          scroll: true,
        ),
      );
      expect(find.text('Q3 产品规划评审'), findsOneWidget);
      expect(find.textContaining('明确激活率目标上调至 35%'), findsOneWidget);
      expect(find.text('32 分钟 · 今天 09:12 · 3 人'), findsOneWidget);
      expect(find.text('已总结'), findsOneWidget);
      await tester.tap(find.text('Q3 产品规划评审'));
      expect(tapped, isTrue);
    });

    testWidgets('无纪要时给出状态兜底文案', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          HistoryCard(summary: _summary(hasMinutes: false, excerpt: '')),
          scroll: true,
        ),
      );
      expect(find.text('暂无纪要'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
    });
  });

  group('AISummaryCard', () {
    testWidgets('摘要默认折叠，点「展开全文」后展示全文', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          AISummaryCard(
            markdown: _minutesMarkdown,
            transcriptChars: 1860,
            modelName: 'qwen3.7-plus',
            onOpenTranscript: () {},
          ),
          scroll: true,
        ),
      );
      expect(find.text('AI 结构化纪要'), findsOneWidget);
      expect(find.text('qwen3.7-plus'), findsOneWidget);
      expect(find.textContaining('展开全文 · 摘要约'), findsOneWidget);
      expect(find.text('收起摘要'), findsNothing);

      await tester.tap(find.textContaining('展开全文 · 摘要约'));
      await tester.pumpAndSettle();
      expect(find.text('收起摘要'), findsOneWidget);
    });

    testWidgets('分节给出「共 N 条」与「查看全部 N 条决策」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          AISummaryCard(
            markdown: _minutesMarkdown,
            transcriptChars: 1860,
            onOpenTranscript: () {},
          ),
          scroll: true,
        ),
      );
      expect(find.textContaining('重要决策'), findsOneWidget);
      expect(find.textContaining('共 3 条'), findsOneWidget);
      expect(find.text('查看全部 3 条决策'), findsOneWidget);

      await tester.tap(find.text('查看全部 3 条决策'));
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      expect(find.textContaining('运营排期提前两周'), findsOneWidget);
    });

    testWidgets('完整转写是独立入口行并带字数', (WidgetTester tester) async {
      bool opened = false;
      await tester.pumpWidget(
        _host(
          AISummaryCard(
            markdown: _minutesMarkdown,
            transcriptChars: 1860,
            onOpenTranscript: () => opened = true,
          ),
          scroll: true,
        ),
      );
      expect(find.text('查看完整转写'), findsOneWidget);
      expect(find.text('1,860 字'), findsOneWidget);
      await tester.tap(find.text('查看完整转写'));
      expect(opened, isTrue);
    });

    testWidgets('生成中展示骨架，出错展示重试', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const AISummaryCard(
            markdown: '',
            transcriptChars: 0,
            generating: true,
            onOpenTranscript: _noop,
          ),
          scroll: true,
        ),
      );
      expect(find.text('生成中'), findsOneWidget);
      expect(find.text('正在生成结构化纪要…'), findsOneWidget);

      bool retried = false;
      await tester.pumpWidget(
        _host(
          AISummaryCard(
            markdown: '',
            transcriptChars: 0,
            error: '生成中断：请求超时',
            onRetry: () => retried = true,
            onOpenTranscript: _noop,
          ),
          scroll: true,
        ),
      );
      expect(find.text('生成中断：请求超时'), findsOneWidget);
      await tester.tap(find.text('重新生成'));
      expect(retried, isTrue);
    });
  });

  group('ActionRow', () {
    testWidgets('三键回调（暂停 / 结束并生成 / 书签）', (WidgetTester tester) async {
      int pause = 0;
      int finish = 0;
      int bookmark = 0;
      await tester.pumpWidget(
        _host(
          ActionRow(
            paused: false,
            onTogglePause: () => pause++,
            onFinish: () => finish++,
            onBookmark: () => bookmark++,
          ),
        ),
      );
      expect(find.text('结束并生成'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.text('结束并生成'));
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      expect(pause, 1);
      expect(finish, 1);
      expect(bookmark, 1);
    });
  });

  group('MeetingInfoCard / EmptyState / AppToast', () {
    testWidgets('信息卡展示标题、徽标与元信息', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const MeetingInfoCard(
            title: 'Q3 产品规划评审',
            meta: '3 小时 12 分钟 · 8 位说话人 · 今天 09:12',
            badgeLabel: '已完成',
          ),
        ),
      );
      expect(find.text('Q3 产品规划评审'), findsOneWidget);
      expect(find.text('3 小时 12 分钟 · 8 位说话人 · 今天 09:12'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
    });

    testWidgets('空态可带动作', (WidgetTester tester) async {
      bool acted = false;
      await tester.pumpWidget(
        _host(
          EmptyState(
            icon: Icons.search_off_rounded,
            title: '没有找到「渠道」',
            description: '试试更短的关键词',
            actionLabel: '清除筛选',
            onAction: () => acted = true,
          ),
        ),
      );
      await tester.tap(find.text('清除筛选'));
      expect(acted, isTrue);
    });

    testWidgets('Toast 从顶部滑入并在清除后隐藏', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const AppToastOverlay(
            message: ToastMessage(text: '网络波动，正在自动重连…', tone: ToastTone.warning),
            child: SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络波动，正在自动重连…'), findsOneWidget);

      await tester.pumpWidget(
        _host(const AppToastOverlay(message: null, child: SizedBox.expand())),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络波动，正在自动重连…'), findsNothing);
    });
  });

  group('AppShell', () {
    testWidgets('三个 Tab 常驻，命中态由 location 推导', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const AppShell(location: '/history', child: SizedBox.expand()),
        ),
      );
      expect(find.text('录音'), findsOneWidget);
      expect(find.text('历史'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    });
  });
}

void _noop() {}
