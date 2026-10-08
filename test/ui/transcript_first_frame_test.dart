/// 问题 4 回归：从纪要页进逐字稿页**不得闪一下**。
///
/// 纪要页已加载 `Meeting`，通过 `extra` 传给转写页（`initialMeeting`）。
/// 此时首帧必须直接渲染内容 —— 不得先渲染 `CircularProgressIndicator` / 空态
/// 再异步填充。仅当**真的没有**预热数据（深链直接进入）时才允许 loading。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/pages/transcript_page.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';

/// 一段终稿逐字稿。
const TranscriptSegment _seg = TranscriptSegment(
  meetingId: 'm1',
  segmentId: 'seg_1',
  ordinal: 0,
  speakerId: kPendingSpeakerId,
  speakerName: '说话人 1',
  text: '这是已经加载好的逐字稿内容',
  startTime: 0,
  endTime: 3200,
  confidence: 0.95,
  seqStart: 0,
  seqEnd: 159,
);

Meeting _meeting() => Meeting(
      id: 'm1',
      title: '测试会议',
      createdAt: DateTime(2026, 9, 24, 10),
      durationMs: 60000,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.stopped,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.done,
      transcriptSource: TranscriptSource.filetrans,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      minutesPartial: false,
      minutesMd: '## 摘要',
      segments: const <TranscriptSegment>[_seg],
      speakers: const <Speaker>[],
    );

class _FakeBackend implements BackendApi {

  // ── 导入音视频（BackendApi 增量 stub：导入流程不在本 UI 测试范围）──

  @override
  Future<Meeting> startImport(ImportRequest req) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelImport(String meetingId) async {}

  @override
  Future<void> retryImport(String meetingId) async {}

  @override
  Stream<ImportProgressEvent> get importEvents =>
      const Stream<ImportProgressEvent>.empty();
  _FakeBackend(this.meeting);

  final Meeting meeting;

  @override
  Future<Meeting?> getMeeting(String id) async => meeting;

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) =>
      const Stream<List<TranscriptSegment>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_FakeBackend backend, {Meeting? initial}) => ProviderScope(
      overrides: [
        backendProvider.overrideWith((Ref ref) async => backend),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: TranscriptPage(meetingId: 'm1', initialMeeting: initial),
      ),
    );

void main() {
  testWidgets('带 initialMeeting：首帧即渲染内容（无 loading / 空态）', (WidgetTester tester) async {
    final _FakeBackend backend = _FakeBackend(_meeting());
    await tester.pumpWidget(_host(backend, initial: _meeting()));

    // 只渲染首帧（不等待异步加载）。
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '数据已在内存中时不得再走一次 loading（这就是"闪一下"）',
    );
    expect(find.byType(TranscriptTile), findsOneWidget, reason: '首帧就应有逐字稿条目');
    expect(find.textContaining('测试会议'), findsOneWidget);

    // 让异步加载收敛，确认不会把内容清空、不抛异常。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TranscriptTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 initialMeeting（深链）：首帧仍为 loading（真无数据才空态）', (WidgetTester tester) async {
    final _FakeBackend backend = _FakeBackend(_meeting());
    await tester.pumpWidget(_host(backend));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
