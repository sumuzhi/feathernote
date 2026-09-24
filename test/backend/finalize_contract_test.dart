import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/finalize_poller.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

/// Bug 2 回归：「结束并生成」无限转圈。
///
/// 根因：`FinalizePoller.start` 把「上传整段 WAV + 提交 filetrans」这段网络耗时
/// 操作 await 在了它返回的 future 里，而 `transcription_service.onStop` 又
/// `await startFinalize(...)`，于是停录路径被上传阻塞 → 按钮一直转圈。
///
/// 契约（本测试固化）：`start` 返回时**只保证 `finalize_status='pending'` 已落盘**，
/// 提交 / 轮询在后台继续，不得阻塞调用方。
void main() {
  group('FinalizePoller.start 契约（Bug 2 · 停录不阻塞）', () {
    test('提交仍在途时 start 已返回，且 pending 已落盘', () async {
      final _FakeRepo repo = _FakeRepo()..seed('m1');
      final _BlockingSubmitEngine engine = _BlockingSubmitEngine();
      final FinalizePoller poller = FinalizePoller(
        engine: engine,
        persistence: repo,
        cfg: AppConfig.defaults(),
      );

      // 引擎的 submit 挂起不返回，模拟弱网下的大文件上传。
      final Future<String> accepted = poller.start('m1', wavPath: '/tmp/m1.wav');

      // 关键断言：调用方立刻拿到控制权（不 await 上传 / 提交）。
      await accepted.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('start 被上传 / 提交阻塞了：停录会一直转圈'),
      );

      // pending 已落盘，刷新页面也能识别「有终稿在处理中」。
      expect(repo.saved['m1']?.finalizeStatus, FinalizeStatus.pending);
      expect(engine.submitStarted, isTrue, reason: '上传 / 提交应在后台继续进行');

      // 放开后台链路，确认最终能走到 done。
      engine.completeSubmit('task-1');
      await _waitForStatus(repo, 'm1', FinalizeStatus.done);
      expect(engine.waitFiletransCalled.isCompleted, isTrue);
    });

    test('后台终稿失败时落成 failed，不影响 start 的返回', () async {
      final _FakeRepo repo = _FakeRepo()..seed('m2');
      final _BlockingSubmitEngine engine = _BlockingSubmitEngine(failSubmit: true);
      final FinalizePoller poller = FinalizePoller(
        engine: engine,
        persistence: repo,
        cfg: AppConfig.defaults(),
      );

      await poller
          .start('m2', wavPath: '/tmp/m2.wav')
          .timeout(const Duration(seconds: 1));
      expect(repo.saved['m2']?.finalizeStatus, FinalizeStatus.pending);

      engine.completeSubmitError(StateError('上传失败'));
      await _waitForStatus(repo, 'm2', FinalizeStatus.failed);
    });

    test('会议不存在时 start 立即报错（同步可判定的失败仍要抛）', () async {
      final _FakeRepo repo = _FakeRepo();
      final _BlockingSubmitEngine engine = _BlockingSubmitEngine();
      final FinalizePoller poller = FinalizePoller(
        engine: engine,
        persistence: repo,
        cfg: AppConfig.defaults(),
      );
      await expectLater(
        poller.start('missing', wavPath: '/tmp/x.wav'),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// 轮询等待某个会议的终稿状态变为 [want]。
///
/// 上限 10 秒：`_withRetry` 对可重试错误有 1s + 2s 的指数退避，需留足余量。
Future<void> _waitForStatus(_FakeRepo repo, String id, FinalizeStatus want) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (repo.saved[id]?.finalizeStatus == want) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待 $id 的 finalizeStatus 变为 $want 超时，当前=${repo.saved[id]?.finalizeStatus}');
}

/// 最小内存仓储（只实现终稿链路用到的能力）。
class _FakeRepo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

  void seed(String id) {
    saved[id] = Meeting(
      id: id,
      title: 'Q3 产品规划评审',
      createdAt: DateTime(2026, 9, 24, 9, 12),
      durationMs: 30000,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.stopped,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.none,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      minutesPartial: false,
      segments: const <TranscriptSegment>[],
      speakers: const <Speaker>[],
    );
  }

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  Future<void> saveMeeting(Meeting meeting) async => saved[meeting.id] = meeting;

  @override
  Future<void> saveFiletransRaw(String meetingId, String json) async {}

  @override
  Future<String?> loadFiletransRaw(String meetingId) async => null;

  @override
  Future<List<MeetingSummary>> listMeetings() async =>
      saved.values.map((Meeting m) => m.toSummary()).toList(growable: false);

  @override
  Future<void> deleteMeeting(String id) async => saved.remove(id);

  @override
  Future<void> updateTitle(String id, String title) async {}

  @override
  Future<int?> schemaVersion() async => 1;

  @override
  Stream<List<MeetingSummary>> watchMeetings() => const Stream<List<MeetingSummary>>.empty();

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) =>
      const Stream<List<TranscriptSegment>>.empty();
}

/// 可控的引擎：`submitFiletrans` 挂起到测试显式放行。
class _BlockingSubmitEngine implements Engine {
  _BlockingSubmitEngine({this.failSubmit = false});

  final bool failSubmit;
  final Completer<String> _submit = Completer<String>();
  final Completer<void> waitFiletransCalled = Completer<void>();
  bool submitStarted = false;

  void completeSubmit(String taskId) {
    if (!_submit.isCompleted) _submit.complete(taskId);
  }

  void completeSubmitError(Object error) {
    if (!_submit.isCompleted) _submit.completeError(error);
  }

  @override
  String get name => 'fake';

  @override
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true}) {
    submitStarted = true;
    return _submit.future;
  }

  @override
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval}) async {
    if (!waitFiletransCalled.isCompleted) waitFiletransCalled.complete();
    return _okResult;
  }

  @override
  Stream<StreamEvent> startRealtimeSession({required String sessionId, required int sampleRate}) =>
      const Stream<StreamEvent>.empty();

  @override
  bool isRealtimeRunning(String sessionId) => false;

  @override
  bool feedRealtime(String sessionId, Uint8List pcm16le) => false;

  @override
  Future<void> stopRealtimeSession(String sessionId) async {}

  @override
  void abortRealtimeSession(String sessionId) {}

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) =>
      const Stream<String>.empty();

  @override
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) async => '';

  @override
  Future<void> dispose() async {}
}

/// 成功结果：**零片段**，避免触发说话人聚类等重逻辑。
const FiletransResult _okResult = FiletransResult(
  status: 'SUCCEEDED',
  segments: <TranscriptSegment>[],
);
