/// 纪要生成生命周期回归（2026-10-09 修复「未生成完退出重进会从头再生成」）。
///
/// 核心语义变更：生成生命周期上收到 `MinutesService`（per-meeting 单飞），
/// 订阅者退出只是「不再观看」，生成继续跑完并落盘**完整**纪要；重进时附着
/// 现有流（重放 + 续收），绝不重复调 LLM。旧语义「取消即落残篇」正是
/// 历史 desc（摘录自旧残篇）与最终纪要不一致的根源。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/minutes_service.dart';
import 'package:smart_minutes_flutter/backend/services/prompts.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

Meeting _meeting(String id) => Meeting(
      id: id,
      title: '测试会议',
      createdAt: DateTime(2026, 10, 9, 11),
      durationMs: 60000,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.stopped,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.done,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      minutesPartial: false,
      segments: <TranscriptSegment>[
        for (int i = 0; i < 2; i++)
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

/// 内存仓储（与 minutes_guard_test 同款：窄更新只改纪要列）。
class _Repo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

  @override
  Future<void> saveMeeting(Meeting meeting) async {
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
    final Meeting? m = saved[id];
    if (m == null) return;
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

/// 可编排的假 LLM：每次 chatStream 从队列取一个测试掌控的 controller。
class _ScriptedLlm implements Engine {
  int chatCalls = 0;
  final List<StreamController<String>> _queue = <StreamController<String>>[];

  void enqueue(StreamController<String> controller) => _queue.add(controller);

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) {
    chatCalls++;
    return _queue.removeAt(0).stream;
  }

  @override
  String get name => 'scripted-llm';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 放行微任务与异步落盘。
Future<void> _settle() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  setUp(() {
    setMinutesTemplateForTesting('模板开始 {{meeting_content}} 模板结束');
  });
  tearDown(clearMinutesTemplateCache);

  test('生成进行中重进 → 附着现有流（重放 + 续收），LLM 只调一次', () async {
    final _Repo repo = _Repo()..saved['m1'] = _meeting('m1');
    final _ScriptedLlm llm = _ScriptedLlm();
    final MinutesService svc = MinutesService(
      engine: llm,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );
    final StreamController<String> engine = StreamController<String>();
    llm.enqueue(engine);

    final List<String> gotA = <String>[];
    final StreamSubscription<String> subA = svc
        .generateStream('m1')
        .listen(gotA.add);
    await _settle();
    engine.add('第一段');
    await _settle();

    // 「退出后重进」：第二个订阅者附着同一轮生成。
    final List<String> gotB = <String>[];
    final StreamSubscription<String> subB = svc
        .generateStream('m1')
        .listen(gotB.add);
    await _settle();

    engine.add('第二段');
    await engine.close();
    await _settle();
    await subA.cancel();
    await subB.cancel();

    expect(llm.chatCalls, 1, reason: '重进必须附着现有生成，绝不重复调 LLM');
    expect(gotA.join(), '第一段第二段');
    expect(gotB.join(), '第一段第二段', reason: '附着者先收到重放，再续收增量');
    expect(repo.saved['m1']!.minutesMd, '第一段第二段');
    expect(repo.saved['m1']!.minutesPartial, isFalse);
    expect(repo.saved['m1']!.status, MeetingStatus.minutesReady);
  });

  test('订阅者中途取消 → 生成继续跑完并落盘完整纪要（不再落残篇）', () async {
    final _Repo repo = _Repo()..saved['m1'] = _meeting('m1');
    final _ScriptedLlm llm = _ScriptedLlm();
    final MinutesService svc = MinutesService(
      engine: llm,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );
    final StreamController<String> engine = StreamController<String>();
    llm.enqueue(engine);

    final StreamSubscription<String> sub = svc
        .generateStream('m1')
        .listen((String _) {});
    await _settle();
    engine.add('部分内容');
    await _settle();

    // 「退出详情页」：取消订阅。
    await sub.cancel();
    engine.add('后续内容');
    await engine.close();
    await _settle();

    final Meeting after = repo.saved['m1']!;
    expect(llm.chatCalls, 1, reason: '取消订阅不得中止生成');
    expect(after.minutesMd, '部分内容后续内容', reason: '必须落盘完整纪要而非残篇');
    expect(after.minutesPartial, isFalse, reason: '不再因订阅取消降级为残篇');
    expect(after.status, MeetingStatus.minutesReady);
  });

  test('force 重启 → 旧流作废不落盘，新一轮落盘自己的内容', () async {
    final _Repo repo = _Repo()..saved['m1'] = _meeting('m1');
    final _ScriptedLlm llm = _ScriptedLlm();
    final MinutesService svc = MinutesService(
      engine: llm,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );
    final StreamController<String> engine1 = StreamController<String>();
    llm.enqueue(engine1);

    final StreamSubscription<String> sub1 = svc
        .generateStream('m1')
        .listen((String _) {});
    await _settle();
    engine1.add('旧内容');
    await _settle();

    // force（终稿完成换稿重生成 / 手动重试）：作废旧流。
    final StreamController<String> engine2 = StreamController<String>();
    llm.enqueue(engine2);
    final List<String> got2 = <String>[];
    final StreamSubscription<String> sub2 = svc
        .generateStream('m1', force: true)
        .listen(got2.add);
    await _settle();
    await engine1.close(); // 旧引擎流自然结束 → 旧任务按作废退出
    engine2.add('新内容');
    await engine2.close();
    await _settle();
    await sub1.cancel();
    await sub2.cancel();

    expect(llm.chatCalls, 2);
    expect(repo.saved['m1']!.minutesMd, '新内容', reason: '只有新一轮落盘');
    expect(repo.saved['m1']!.minutesPartial, isFalse);
  });
}
