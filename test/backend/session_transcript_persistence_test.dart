/// 问题 3 回归：**实时逐字稿必须真的落库**（不能「UI 有、库里空」）。
///
/// 历史缺陷链：实时句子经 `_handleRealtimeEvent` → `sessionStore.upsertSegment`
/// 入库；停录时 `onStop` 用 `findByMeeting(meetingId)` 反查会话。一旦
///   ① 会话态被清空 / `meetingId` 未写对（`getOrCreate` 旧实现不更新 meetingId），
///   ② 反查不到 → 走不到会话态逐字稿分支，
/// 就会「实时能上屏、落库逐字稿为空」。
///
/// 本文件用**真实 TranscriptionService + SessionStore** + 假引擎 / 假仓储，固化：
///   1. 实时句 → `onStop` 落库非空（`findByMeeting` 路径）；
///   2. `SessionStore.getOrCreate` 的合并语义（补齐 / 纠正 meetingId）；
///   3. 会话态被清空后仍有事件 → **自动重建**，后续句不再丢；
///   4. `onStop` 支持显式 sessionId，**不依赖反查**也能救回；
///   5. 终稿返回**空结果**不得把已落的实时稿擦成空。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/session_store.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/backend/storage/audio_archive.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

/// 让事件循环转几圈（流事件 + 多段 await 链收敛）。
Future<void> _settle() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Meeting _meeting(String id) => Meeting(
      id: id,
      title: '测试会议',
      createdAt: DateTime(2026, 9, 24, 10),
      durationMs: 0,
      sampleRate: 16000,
      speakerCount: 0,
      status: MeetingStatus.recording,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.none,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.none,
      audioBytes: 0,
      minutesPartial: false,
      segments: const <TranscriptSegment>[],
      speakers: const <Speaker>[],
    );

/// 内存仓储（只实现本用例用到的读 / 写）。
class _InMemoryRepo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

  @override
  Future<void> saveMeeting(Meeting meeting) async => saved[meeting.id] = meeting;

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 空归档（本用例 `upload: false`，不会调用）。
class _NullArchive implements AudioArchive {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 假引擎：可控地在某会话上「产出」实时句子。
class _FakeEngine implements Engine {
  final Map<String, StreamController<StreamEvent>> _controllers =
      <String, StreamController<StreamEvent>>{};

  @override
  String get name => 'fake';

  @override
  Stream<StreamEvent> startRealtimeSession({
    required String sessionId,
    required int sampleRate,
  }) {
    final StreamController<StreamEvent> controller = StreamController<StreamEvent>();
    _controllers[sessionId] = controller;
    return controller.stream;
  }

  @override
  bool isRealtimeRunning(String sessionId) => true;

  @override
  bool feedRealtime(String sessionId, Uint8List pcm16le) => true;

  @override
  Future<void> stopRealtimeSession(String sessionId) async {}

  @override
  void abortRealtimeSession(String sessionId) {}

  /// 测试驱动：模拟服务端产出一句（最终句）。
  void emitSentence(
    String sessionId, {
    required String id,
    required String text,
    int start = 0,
    int end = 1000,
  }) {
    _controllers[sessionId]!.add(
      StreamEvent(
        segmentId: id,
        speakerId: kPendingSpeakerId,
        text: text,
        startTime: start,
        endTime: end,
        isFinal: true,
        confidence: 0.9,
      ),
    );
  }

  /// 关闭全部事件流（收尾）。
  Future<void> closeAll() async {
    for (final StreamController<StreamEvent> controller in _controllers.values) {
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

({TranscriptionService svc, SessionStore store, _FakeEngine engine, _InMemoryRepo repo})
    _boot() {
  final SessionStore store = SessionStore();
  final _FakeEngine engine = _FakeEngine();
  final _InMemoryRepo repo = _InMemoryRepo();
  final TranscriptionService svc = TranscriptionService(
    engine: engine,
    sessionStore: store,
    persistence: repo,
    archive: _NullArchive(),
    cfg: AppConfig.defaults(),
  );
  return (svc: svc, store: store, engine: engine, repo: repo);
}

void main() {
  const MethodChannel pathProvider =
      MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 让 `getTemporaryDirectory()` 在测试里可用（PCM 临时写盘）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getApplicationDocumentsDirectory') {
        return Directory.systemTemp.createTempSync('sm_test_').path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  test('实时句 → onStop 落库非空（findByMeeting 路径）', () async {
    final ({TranscriptionService svc, SessionStore store, _FakeEngine engine, _InMemoryRepo repo})
        b = _boot();
    addTearDown(() async {
      await b.svc.dispose();
      await b.engine.closeAll();
    });
    await b.repo.saveMeeting(_meeting('m1'));

    await b.svc.startSession(sessionId: 's1', meetingId: 'm1');
    b.engine.emitSentence('s1', id: 'seg_1', text: '第一句', start: 0, end: 1000);
    b.engine.emitSentence('s1', id: 'seg_2', text: '第二句', start: 1200, end: 2400);
    await _settle();

    expect(b.store.transcript('s1').length, 2, reason: '会话态应累计两句');
    expect(b.store.findByMeeting('m1'), isNotNull, reason: 'meetingId 必须可反查');

    // 不带 sessionId，强制走 findByMeeting 反查路径。
    final Meeting? stopped = await b.svc.onStop('m1', upload: false);
    expect(stopped, isNotNull);
    final Meeting stored = (await b.repo.loadMeeting('m1'))!;
    expect(
      stored.segments.map((TranscriptSegment s) => s.text).toList(),
      <String>['第一句', '第二句'],
      reason: '实时句必须落库（历史 Bug：这里为空）',
    );
  });

  test('SessionStore.getOrCreate 合并语义：补齐 / 纠正 meetingId', () {
    final SessionStore store = SessionStore();
    // 先以空 meetingId 建（模拟历史缺陷下的「先建后补」）。
    store.create('s1', meetingId: '');
    expect(store.findByMeeting('m1'), isNull);

    final SessionState state = store.getOrCreate('s1', meetingId: 'm1');
    expect(state.meetingId, 'm1', reason: 'getOrCreate 必须把 meetingId 补上');
    expect(store.findByMeeting('m1'), isNotNull);
  });

  test('会话态被清空后仍有事件 → 自动重建，不丢后续句', () async {
    final ({TranscriptionService svc, SessionStore store, _FakeEngine engine, _InMemoryRepo repo})
        b = _boot();
    addTearDown(() async {
      await b.svc.dispose();
      await b.engine.closeAll();
    });
    await b.repo.saveMeeting(_meeting('m1'));
    await b.svc.startSession(sessionId: 's1', meetingId: 'm1');

    // 模拟「录音中会话态被清空」（历史成因之一）。
    b.store.clear();
    expect(b.store.get('s1'), isNull);

    b.engine.emitSentence('s1', id: 'seg_1', text: '重启后第一句');
    await _settle();

    expect(b.store.get('s1'), isNotNull, reason: '事件到达时应自动重建会话态');
    expect(b.store.transcript('s1').length, 1, reason: '重建后事件必须入库');

    final Meeting? stopped = await b.svc.onStop('m1', upload: false);
    expect(stopped, isNotNull);
    expect((await b.repo.loadMeeting('m1'))!.segments.length, 1);
  });

  test('onStop 支持显式 sessionId：不依赖反查也能落库', () async {
    final ({TranscriptionService svc, SessionStore store, _FakeEngine engine, _InMemoryRepo repo})
        b = _boot();
    addTearDown(() async {
      await b.svc.dispose();
      await b.engine.closeAll();
    });
    await b.repo.saveMeeting(_meeting('m1'));
    await b.svc.startSession(sessionId: 's1', meetingId: 'm1');
    b.engine.emitSentence('s1', id: 'seg_1', text: '唯一一句');
    await _settle();

    // 故意把会话的 meetingId 改乱，令 findByMeeting 失效（模拟反查失败）。
    b.store.get('s1')!.meetingId = 'mX';
    expect(b.store.findByMeeting('m1'), isNull, reason: '此时反查应失败');

    final Meeting? stopped = await b.svc.onStop('m1', sessionId: 's1', upload: false);
    expect(stopped, isNotNull);
    expect(
      (await b.repo.loadMeeting('m1'))!.segments.length,
      1,
      reason: '显式 sessionId 应救回逐字稿（不再依赖反查）',
    );
  });

  test('终稿返回空结果：保留实时稿，不擦成空', () async {
    final ({TranscriptionService svc, SessionStore store, _FakeEngine engine, _InMemoryRepo repo})
        b = _boot();
    addTearDown(() async {
      await b.svc.dispose();
      await b.engine.closeAll();
    });
    await b.repo.saveMeeting(_meeting('m1'));
    await b.svc.startSession(sessionId: 's1', meetingId: 'm1');
    b.engine.emitSentence('s1', id: 'seg_1', text: '实时稿一句');
    await _settle();
    await b.svc.onStop('m1', upload: false);
    expect((await b.repo.loadMeeting('m1'))!.segments.length, 1);

    // 终稿返回空（服务端无有效结果）：不得覆盖掉已有的实时稿。
    await b.svc.handleFinalizeComplete('m1', <TranscriptSegment>[]);

    final Meeting after = (await b.repo.loadMeeting('m1'))!;
    expect(after.segments.length, 1, reason: '空终稿不得擦掉实时稿');
    expect(after.segments.first.text, '实时稿一句');
  });
}
