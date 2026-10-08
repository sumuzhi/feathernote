/// 导入编排服务单测（T3 验收 ③）：状态机全转移 + 恢复逻辑三分支（Mock 引擎）。
///
/// 覆盖：
/// - 音频导入全链路：`import_pending → transcribing → minutes → done`（source=imported）；
/// - 视频导入全链路：含 extracting 步（m4a 归档 `audioKey=<id>.m4a`）；
/// - 取消：upload 阶段取消 → failed('用户取消')；
/// - 转写失败：waitFiletrans FAILED → failed（importError 记录原因）；
/// - 恢复三分支：pending → 标记失败；transcribing+taskId → 续轮询；minutes → 重触发纪要。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType, RequestOptions;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smart_minutes_flutter/backend/engine/bailian/filetrans.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/finalize_poller.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
import 'package:smart_minutes_flutter/backend/services/minutes_service.dart';
import 'package:smart_minutes_flutter/backend/storage/audio_archive.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/platform/media_import_channel.dart';

void main() {
  // prompts.dart 经 rootBundle 读取 assets/prompts/minutes.md → 需要 ServicesBinding。
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late _FakeRepo repo;
  late _FakeImportEngine engine;
  late _FakeFiletrans filetrans;
  late _FakeMediaImport mediaImport;
  late LocalFileArchive archive;
  late ImportService service;
  final List<ImportProgressEvent> events = <ImportProgressEvent>[];
  StreamSubscription<ImportProgressEvent>? eventsSub;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('import_test');
    repo = _FakeRepo();
    engine = _FakeImportEngine();
    filetrans = _FakeFiletrans(AppConfig.defaults());
    mediaImport = _FakeMediaImport();
    archive = LocalFileArchive(baseDir: Directory(p.join(tmpDir.path, 'archive')));
    final FinalizePoller poller = FinalizePoller(
      engine: engine,
      persistence: repo,
      cfg: AppConfig.defaults(),
    );
    service = ImportService(
      persistence: repo,
      filetrans: filetrans,
      finalizePoller: poller,
      minutesService: MinutesService(engine: engine, persistence: repo, cfg: AppConfig.defaults()),
      archive: archive,
      mediaImport: mediaImport,
      cfg: AppConfig.defaults(),
      sandboxRoot: Directory(p.join(tmpDir.path, 'sandbox')),
    );
    events.clear();
    eventsSub = service.events.listen(events.add);
  });

  tearDown(() async {
    await eventsSub?.cancel();
    tmpDir.deleteSync(recursive: true);
  });

  /// 轮询等待条件成立（上限 10 秒）。
  Future<void> waitUntil(bool Function() cond, {String? hint}) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('等待超时：${hint ?? '条件未满足'}');
  }

  test('音频导入全链路：pending → transcribing → minutes → done（source=imported）', () async {
    final File src = File(p.join(tmpDir.path, '录音.mp3'))..writeAsBytesSync(List<int>.filled(2048, 7));
    mediaImport.probeResult = const MediaProbeResult(
      durationMs: 60000,
      hasAudio: true,
      isVideoContainer: false,
      mimeType: 'audio/mpeg',
    );
    engine.taskId = 'task-a1';

    final Meeting meeting = await service.startImport(
      ImportRequest(srcPath: src.path, srcName: '录音.mp3', isVideo: false, sizeBytes: 2048),
    );

    expect(meeting.source, MeetingSource.imported);
    expect(meeting.title, '录音');
    expect(meeting.status, MeetingStatus.stopped);

    await waitUntil(
      () => repo.saved[meeting.id]?.importStatus == ImportStatus.done,
      hint: '音频导入应到 done',
    );
    final Meeting done = repo.saved[meeting.id]!;
    expect(done.importStatus, ImportStatus.done);
    expect(done.importError, isNull);
    expect(done.importTaskId, 'task-a1');
    expect(done.finalizeStatus, FinalizeStatus.done);
    expect(done.transcriptSource, TranscriptSource.filetrans);
    expect(done.status, MeetingStatus.minutesReady);
    expect(done.minutesMd, '导入纪要内容');
    expect(done.segments, hasLength(1));
    // 音频直传：原文件归档（audioKey=<id>.mp3，移动语义）。
    expect(done.audioKey, '${meeting.id}.mp3');
    expect(File(await archive.pathForKey('${meeting.id}.mp3')).existsSync(), isTrue);
    // 流式上传被调用：原文件一次 + （无分离）。
    expect(filetrans.uploadedNames, contains('${meeting.id}.mp3'));

    // 事件序列：至少覆盖 upload running / transcribe running / done。
    expect(
      events.any((ImportProgressEvent e) => e.meetingId == meeting.id && e.step == ImportService.stepUpload && e.status == 'running'),
      isTrue,
    );
    expect(
      events.any((ImportProgressEvent e) => e.meetingId == meeting.id && e.step == ImportService.stepDone && e.status == 'done'),
      isTrue,
    );
  });

  test('视频导入全链路：含 extracting 步，m4a 归档 audioKey=<id>.m4a', () async {
    final File src = File(p.join(tmpDir.path, '会议录像.mp4'))
      ..writeAsBytesSync(List<int>.filled(4096, 9));
    mediaImport.probeResult = const MediaProbeResult(
      durationMs: 120000,
      hasAudio: true,
      isVideoContainer: true,
      mimeType: 'video/mp4',
    );
    mediaImport.extractBytes = 1024;
    mediaImport.extractDurationMs = 119000;
    engine.taskId = 'task-v1';

    final Meeting meeting = await service.startImport(
      ImportRequest(srcPath: src.path, srcName: '会议录像.mp4', isVideo: true, sizeBytes: 4096),
    );

    await waitUntil(
      () => repo.saved[meeting.id]?.importStatus == ImportStatus.done,
      hint: '视频导入应到 done',
    );
    final Meeting done = repo.saved[meeting.id]!;
    expect(done.importStatus, ImportStatus.done);
    expect(done.audioKey, '${meeting.id}.m4a');
    expect(done.durationMs, 119000, reason: 'step2 应把真实音轨时长回写');
    expect(File(await archive.pathForKey('${meeting.id}.m4a')).existsSync(), isTrue);
    // SSOT 附录 A：step1 上传原文件 + step2 后上传 m4a。
    expect(filetrans.uploadedNames, containsAll(<String>['${meeting.id}.mp4', '${meeting.id}.m4a']));
    // extracting 事件出现。
    expect(
      events.any((ImportProgressEvent e) => e.meetingId == meeting.id && e.step == ImportService.stepExtract && e.status == 'running'),
      isTrue,
    );
  });

  test('取消：upload 阶段取消 → failed(用户取消)', () async {
    final File src = File(p.join(tmpDir.path, 'slow.mp3'))
      ..writeAsBytesSync(List<int>.filled(1024, 1));
    mediaImport.probeResult = const MediaProbeResult(
      durationMs: 5000,
      hasAudio: true,
      isVideoContainer: false,
      mimeType: 'audio/mpeg',
    );
    filetrans.hangOnUpload = true;

    final Meeting meeting = await service.startImport(
      ImportRequest(srcPath: src.path, srcName: 'slow.mp3', isVideo: false, sizeBytes: 1024),
    );
    await waitUntil(() => filetrans.uploadStarted, hint: '上传应已开始');
    await service.cancelImport(meeting.id);

    await waitUntil(
      () => repo.saved[meeting.id]?.importStatus == ImportStatus.failed,
      hint: '取消后应落 failed',
    );
    expect(repo.saved[meeting.id]!.importError, '用户取消');
  });

  test('转写失败：waitFiletrans FAILED → failed（importError 记录原因）', () async {
    final File src = File(p.join(tmpDir.path, 'bad.mp3'))
      ..writeAsBytesSync(List<int>.filled(1024, 1));
    mediaImport.probeResult = const MediaProbeResult(
      durationMs: 5000,
      hasAudio: true,
      isVideoContainer: false,
      mimeType: 'audio/mpeg',
    );
    engine.taskId = 'task-bad';
    engine.filetransStatus = 'FAILED';
    engine.filetransError = '音频解码失败';

    final Meeting meeting = await service.startImport(
      ImportRequest(srcPath: src.path, srcName: 'bad.mp3', isVideo: false, sizeBytes: 1024),
    );
    await waitUntil(
      () => repo.saved[meeting.id]?.importStatus == ImportStatus.failed,
      hint: '转写失败应落 failed',
    );
    expect(repo.saved[meeting.id]!.importError, contains('音频解码失败'));
    expect(repo.saved[meeting.id]!.finalizeStatus, FinalizeStatus.failed);
  });

  test('恢复分支 ①：import_pending → 标记 failed(应用退出导致导入中断)', () async {
    repo.seed(
      _seedMeeting('m-rec-pending', importStatus: ImportStatus.importPending),
    );
    await service.recoverOnStartup();
    expect(repo.saved['m-rec-pending']!.importStatus, ImportStatus.failed);
    expect(repo.saved['m-rec-pending']!.importError, '应用退出导致导入中断');
  });

  test('恢复分支 ②：transcribing + taskId → 续轮询 → done', () async {
    engine.taskId = 't9';
    repo.seed(
      _seedMeeting(
        'm-rec-trans',
        importStatus: ImportStatus.transcribing,
        importTaskId: 't9',
      ),
    );
    await service.recoverOnStartup();
    await waitUntil(
      () => repo.saved['m-rec-trans']?.importStatus == ImportStatus.done,
      hint: '恢复轮询后应到 done',
    );
    final Meeting done = repo.saved['m-rec-trans']!;
    expect(done.finalizeStatus, FinalizeStatus.done);
    expect(done.segments, hasLength(1));
    expect(done.minutesMd, '导入纪要内容');
  });

  test('恢复分支 ③：minutes → 重触发纪要 → done', () async {
    repo.seed(
      _seedMeeting('m-rec-minutes', importStatus: ImportStatus.minutes, withSegment: true),
    );
    await service.recoverOnStartup();
    await waitUntil(
      () => repo.saved['m-rec-minutes']?.importStatus == ImportStatus.done,
      hint: '重触发纪要后应到 done',
    );
    expect(repo.saved['m-rec-minutes']!.minutesMd, '导入纪要内容');
  });

  test('恢复对 done/failed/none 不动', () async {
    repo.seed(_seedMeeting('m-done', importStatus: ImportStatus.done));
    repo.seed(_seedMeeting('m-failed', importStatus: ImportStatus.failed));
    await service.recoverOnStartup();
    expect(repo.saved['m-done']!.importStatus, ImportStatus.done);
    expect(repo.saved['m-failed']!.importStatus, ImportStatus.failed);
    expect(engine.submitCalls, 0, reason: '恢复不得重新提交 filetrans');
  });
}

// ───────────────────────────────────────────────────────────────── 测试假件

/// 构造导入会议种子。
Meeting _seedMeeting(
  String id, {
  required ImportStatus importStatus,
  String? importTaskId,
  bool withSegment = false,
}) {
  return Meeting(
    id: id,
    title: '恢复测试会议',
    createdAt: DateTime.now().toUtc(),
    durationMs: 60000,
    sampleRate: 16000,
    speakerCount: 0,
    status: MeetingStatus.stopped,
    source: MeetingSource.imported,
    finalizeStatus: FinalizeStatus.none,
    transcriptSource: TranscriptSource.realtime,
    audioStatus: AudioStatus.none,
    audioBytes: 0,
    minutesPartial: false,
    segments: withSegment
        ? const <TranscriptSegment>[
            TranscriptSegment(
              meetingId: 'm-rec-minutes',
              segmentId: 'seg-1',
              ordinal: 0,
              speakerId: 'spk-1',
              text: '恢复用逐字稿',
              startTime: 0,
              endTime: 3000,
              confidence: 0.9,
              seqStart: 0,
              seqEnd: 29,
            ),
          ]
        : const <TranscriptSegment>[],
    speakers: const <Speaker>[],
    importStatus: importStatus,
    importTaskId: importTaskId,
    importMetaJson: '{"srcName":"x.mp3","srcPath":"/nonexistent/x.mp3","kind":"audio"}',
  );
}

/// 最小内存仓储（只实现导入链路用到的能力）。
class _FakeRepo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

  void seed(Meeting meeting) => saved[meeting.id] = meeting;

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  Future<void> saveMeeting(Meeting meeting) async => saved[meeting.id] = meeting;

  @override
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {
    final Meeting? current = saved[id];
    if (current == null) return;
    saved[id] = current.copyWith(
      minutesMd: minutesMd ?? current.minutesMd,
      status: status ?? current.status,
      minutesPartial: minutesPartial ?? current.minutesPartial,
      minutesError: clearMinutesError ? null : (minutesError ?? current.minutesError),
    );
  }

  @override
  Future<List<MeetingSummary>> listMeetings() async =>
      saved.values.map((Meeting m) => m.toSummary()).toList();

  @override
  Future<void> deleteMeeting(String id) async => saved.remove(id);

  @override
  Future<void> updateTitle(String id, String title) async {}

  @override
  Future<void> saveFiletransRaw(String meetingId, String json) async {}

  @override
  Future<String?> loadFiletransRaw(String meetingId) async => null;

  @override
  Stream<List<MeetingSummary>> watchMeetings() => const Stream<List<MeetingSummary>>.empty();

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) =>
      const Stream<List<TranscriptSegment>>.empty();

  @override
  Future<int?> schemaVersion() async => 2;
}

/// 导入测试引擎：submit/wait 可编排，chat 固定产出。
class _FakeImportEngine implements Engine {
  String taskId = 'task-x';
  String filetransStatus = 'SUCCEEDED';
  String? filetransError;
  int submitCalls = 0;

  @override
  String get name => 'fake-import';

  @override
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true}) async {
    submitCalls++;
    return taskId;
  }

  @override
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval}) async {
    if (filetransStatus == 'SUCCEEDED') {
      return const FiletransResult(
        status: 'SUCCEEDED',
        segments: <TranscriptSegment>[
          TranscriptSegment(
            meetingId: 'any',
            segmentId: 'seg-1',
            ordinal: 0,
            speakerId: 'spk-1',
            text: '导入转写句子',
            startTime: 0,
            endTime: 3000,
            confidence: 0.9,
            seqStart: 0,
            seqEnd: 29,
          ),
        ],
      );
    }
    return FiletransResult(status: filetransStatus, segments: const <TranscriptSegment>[], error: filetransError);
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) async* {
    yield '导入纪要内容';
  }

  @override
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) async => '导入纪要内容';

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
  Future<void> pauseRealtimeSession(String sessionId) async {}

  @override
  Future<void> resumeRealtimeSession(String sessionId) async {}

  @override
  void abortRealtimeSession(String sessionId) {}

  @override
  Future<void> dispose() async {}
}

/// 流式上传假件（可挂起模拟弱网，可注入取消）。
class _FakeFiletrans extends BailianFiletrans {
  _FakeFiletrans(super.cfg);

  final List<String> uploadedNames = <String>[];
  bool hangOnUpload = false;
  bool uploadStarted = false;

  @override
  Future<String> uploadLocalFileStream(
    String filePath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
    String? filename,
    String? model,
  }) async {
    uploadStarted = true;
    uploadedNames.add(filename ?? filePath.split(Platform.pathSeparator).last);
    if (!hangOnUpload) {
      onProgress?.call(1024, 2048);
      return 'oss://fake/upload/$filename';
    }
    // 挂起直到取消（模拟弱网大文件上传）。
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: 'oss://fake'),
          type: DioExceptionType.cancel,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('上传假件超时');
  }
}

/// 平台通道假件（probe / extract 内存实现）。
class _FakeMediaImport extends MediaImportChannel {
  _FakeMediaImport() : super(channel: _unusedChannel);

  static const MethodChannel _unusedChannel = MethodChannel('unused');

  MediaProbeResult probeResult = const MediaProbeResult(
    durationMs: 1000,
    hasAudio: true,
    isVideoContainer: false,
    mimeType: 'audio/mpeg',
  );
  int extractBytes = 0;
  int extractDurationMs = 0;

  @override
  Future<MediaProbeResult> probeMedia(String path) async => probeResult;

  @override
  Future<MediaExtractResult> extractAudioTrack(String token, String srcPath, String destPath) async {
    File(destPath).writeAsBytesSync(List<int>.filled(extractBytes, 3));
    return MediaExtractResult(path: destPath, durationMs: extractDurationMs, bytesWritten: extractBytes);
  }

  @override
  Future<bool> cancelExtract(String token) async => true;
}
