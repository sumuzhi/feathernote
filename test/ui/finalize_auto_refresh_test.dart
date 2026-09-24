/// Task B 回归：纪要页的「终稿自动刷新」必须**真的会刷新**。
///
/// 历史缺陷：`meeting_page` 的文案写「终稿处理中 · 完成后自动刷新纪要」，
/// 但页面从未订阅 `FinalizeProgress`，实际永远不会自动刷新（文案在骗用户）。
///
/// 本文件固化修复后的契约：
/// 1. `finalize_status` pending → 展示「完成后自动刷新」提示；
/// 2. 收到 `done` → **重新拉取会议详情**（终稿逐字稿替换后重生成纪要）；
/// 3. 收到 `failed` → 展示**可读失败原因**。
///
/// 注意：`MeetingPage` 加载态含无限动画（`CircularProgressIndicator`），
/// 因此这里不用 `pumpAndSettle`，改用固定步长 `pump`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/pages/meeting_page.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';

const String _minutesMd = '## 摘要\n\n这是一段摘要\n\n## 要点\n\n- 要点一\n- 要点二';

Meeting _meeting({
  required FinalizeStatus finalize,
  String? minutesMd = _minutesMd,
  String? finalizeError,
  int durationMs = 60000,
  List<TranscriptSegment> segments = const <TranscriptSegment>[],
}) =>
    Meeting(
      id: 'm1',
      title: 'Q3 产品规划评审',
      createdAt: DateTime(2026, 9, 24, 9, 12),
      durationMs: durationMs,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.stopped,
      source: MeetingSource.microphone,
      finalizeStatus: finalize,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      minutesPartial: false,
      minutesMd: minutesMd,
      finalizeError: finalizeError,
      segments: segments,
      speakers: const <Speaker>[],
    );

TranscriptSegment _seg(String id) => TranscriptSegment(
      meetingId: 'm1',
      segmentId: id,
      ordinal: 0,
      speakerId: 'spk_1',
      text: '终稿句子',
      startTime: 0,
      endTime: 1000,
      confidence: 0.9,
      seqStart: 0,
      seqEnd: 49,
    );

/// 固定步长推进若干帧（不做 `pumpAndSettle`：加载态是无限动画）。
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 最小假后端：可变的会议快照 + 可推送的事件流。
class _FakeBackend implements BackendApi {
  _FakeBackend(this.meeting);

  Meeting meeting;
  int getMeetingCalls = 0;
  int generateCalls = 0;
  final StreamController<TranscriptEvent> eventsCtrl =
      StreamController<TranscriptEvent>.broadcast();

  void emit(TranscriptEvent event) => eventsCtrl.add(event);

  @override
  Stream<TranscriptEvent> get events => eventsCtrl.stream;

  @override
  Future<Meeting?> getMeeting(String id) async {
    getMeetingCalls++;
    return meeting;
  }

  @override
  Stream<String> generateMinutesStream(String meetingId, {bool force = false}) async* {
    generateCalls++;
    yield '## 新摘要\n\n（依据终稿重新生成）';
  }

  @override
  Stream<List<MeetingSummary>> watchMeetings() => const Stream<List<MeetingSummary>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_FakeBackend backend) => ProviderScope(
      overrides: [
        backendProvider.overrideWith((Ref ref) async => backend),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const MeetingPage(meetingId: 'm1'),
      ),
    );

void main() {
  testWidgets('pending → done：自动刷新会议详情并用终稿重生成纪要', (WidgetTester tester) async {
    final _FakeBackend backend = _FakeBackend(_meeting(finalize: FinalizeStatus.pending));
    await tester.pumpWidget(_host(backend));
    await _settle(tester);

    expect(backend.getMeetingCalls, 1, reason: '初始加载一次');
    expect(find.textContaining('终稿处理中'), findsOneWidget, reason: 'pending 应显示处理中提示');

    // 终稿完成：逐字稿由 filetrans 替换（segment 数变化）、时长变化。
    backend.meeting = _meeting(
      finalize: FinalizeStatus.done,
      durationMs: 90000,
      segments: <TranscriptSegment>[_seg('seg_1')],
    );
    backend.emit(FinalizeProgress(meetingId: 'm1', status: 'done'));
    await _settle(tester);

    expect(
      backend.getMeetingCalls,
      greaterThanOrEqualTo(2),
      reason: '收到 done 必须重新拉取会议详情（原来的假自动刷新就是没做这一步）',
    );
    expect(find.textContaining('终稿处理中'), findsNothing, reason: '完成后不再显示处理中');
    expect(
      backend.generateCalls,
      greaterThanOrEqualTo(1),
      reason: '逐字稿被终稿替换后应重新生成纪要',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending → failed：展示可读失败原因，且文案不骗用户', (WidgetTester tester) async {
    final _FakeBackend backend = _FakeBackend(_meeting(finalize: FinalizeStatus.pending));
    await tester.pumpWidget(_host(backend));
    await _settle(tester);
    expect(find.textContaining('终稿处理中'), findsOneWidget);

    backend.meeting = _meeting(finalize: FinalizeStatus.failed, finalizeError: '网络超时');
    backend.emit(
      FinalizeProgress(meetingId: 'm1', status: 'failed', error: '网络超时'),
    );
    await _settle(tester);

    expect(find.textContaining('终稿失败'), findsOneWidget);
    expect(find.textContaining('网络超时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('其它会议的事件不影响本页（meetingId 过滤）', (WidgetTester tester) async {
    final _FakeBackend backend = _FakeBackend(_meeting(finalize: FinalizeStatus.pending));
    await tester.pumpWidget(_host(backend));
    await _settle(tester);

    backend.emit(FinalizeProgress(meetingId: 'other', status: 'done'));
    await _settle(tester);

    expect(backend.getMeetingCalls, 1, reason: '别的会议的 done 不应触发本页刷新');
    expect(find.textContaining('终稿处理中'), findsOneWidget);
  });
}
