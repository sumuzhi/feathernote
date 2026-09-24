/// P0-2 回归：①**空逐字稿拒绝生成**（不得产出无源摘要）；
/// ②纪要落盘走**窄更新**（`updateMinutes`），**绝不整体回写** Meeting —
/// 否则会用一份过期副本把逐字稿 `segments` 擦成 0（「读-改-写覆盖」）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/minutes_service.dart';
import 'package:smart_minutes_flutter/backend/services/prompts.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/core/error/app_error.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

Meeting _meeting(String id, {int segments = 0}) => Meeting(
      id: id,
      title: '测试会议',
      createdAt: DateTime(2026, 9, 24, 10),
      durationMs: 60000,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.stopped,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.none,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      minutesPartial: false,
      segments: <TranscriptSegment>[
        for (int i = 0; i < segments; i++)
          TranscriptSegment(
            meetingId: id,
            segmentId: 'seg_$i',
            ordinal: i,
            speakerId: 'spk_1',
            text: '第 $i 句内容',
            startTime: i * 1000,
            endTime: i * 1000 + 800,
            confidence: 0.9,
            seqStart: i,
            seqEnd: i,
          ),
      ],
      speakers: const <Speaker>[],
    );

/// 内存仓储：记录 `saveMeeting` / `updateMinutes` 调用次数；窄更新**不动**逐字稿。
class _Repo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};
  int saveMeetingCount = 0;
  int updateMinutesCount = 0;

  @override
  Future<void> saveMeeting(Meeting meeting) async {
    saveMeetingCount++;
    saved[meeting.id] = meeting;
  }

  @override
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {
    updateMinutesCount++;
    final Meeting? m = saved[id];
    if (m == null) return;
    // 只改纪要四列，其余（含 segments / speakers）原样保留。
    saved[id] = Meeting(
      id: m.id,
      title: m.title,
      createdAt: m.createdAt,
      durationMs: m.durationMs,
      sampleRate: m.sampleRate,
      speakerCount: m.speakerCount,
      status: status ?? m.status,
      source: m.source,
      finalizeStatus: m.finalizeStatus,
      transcriptSource: m.transcriptSource,
      audioStatus: m.audioStatus,
      audioBytes: m.audioBytes,
      minutesPartial: minutesPartial ?? m.minutesPartial,
      minutesMd: minutesMd ?? m.minutesMd,
      minutesError: clearMinutesError ? null : (minutesError ?? m.minutesError),
      finalizeError: m.finalizeError,
      audioKey: m.audioKey,
      audioError: m.audioError,
      segments: m.segments,
      speakers: m.speakers,
    );
  }

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 假 LLM：可统计调用次数，按需产出。
class _Llm implements Engine {
  int chatCalls = 0;

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) async* {
    chatCalls++;
    yield '生成内容';
  }

  @override
  String get name => 'fake-llm';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('逐字稿为空 → 拒绝生成，不调用 LLM、不落盘', () async {
    final _Repo repo = _Repo()..saved['m1'] = _meeting('m1');
    final _Llm llm = _Llm();
    final MinutesService svc = MinutesService(
      engine: llm,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );

    await expectLater(
      svc.generateStream('m1').toList(),
      throwsA(isA<AppError>()),
    );
    expect(llm.chatCalls, 0, reason: '绝不给 LLM 喂空逐字稿');
    expect(repo.updateMinutesCount, 0);
    expect(repo.saved['m1']!.minutesMd, isNull, reason: '不得产出任何无源摘要');
  });

  test('生成成功：走窄更新，绝不整体回写，逐字稿不被擦', () async {
    setMinutesTemplateForTesting('模板开始 {{meeting_content}} 模板结束');
    addTearDown(clearMinutesTemplateCache);

    final _Repo repo = _Repo()..saved['m1'] = _meeting('m1', segments: 2);
    final _Llm llm = _Llm();
    final MinutesService svc = MinutesService(
      engine: llm,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );

    final String out = await svc.generate('m1');
    expect(out, '生成内容');
    expect(llm.chatCalls, 1);

    expect(repo.saveMeetingCount, 0, reason: '纪要落盘绝不能整体回写 Meeting');
    expect(repo.updateMinutesCount, greaterThanOrEqualTo(1), reason: '必须走窄更新');

    final Meeting after = repo.saved['m1']!;
    expect(after.minutesMd, '生成内容');
    expect(after.status, MeetingStatus.minutesReady);
    expect(after.minutesPartial, isFalse);
    expect(after.segments.length, 2, reason: '逐字稿绝不能被纪要落盘擦成 0');
  });
}
