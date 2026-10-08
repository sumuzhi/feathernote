/// P0-1 回归：`onStop` 的 WAV 收尾必须是**流式补头**（不整份 `readAsBytes`），
/// 产出的是**合法 WAV**（RIFF/WAVE 头 + PCM），且**逐字稿先落库**再触发终稿。
///
/// 历史缺陷：旧 `finishWav` = `flush → close → readAsBytes(整份 PCM) → buildWav`
/// （整份读回内存 + 二次拷贝）。长录音下该步阻塞 >10s，撞上 UI `kStopTimeout`
/// → UI 误判"收尾完成"继续跳详情页并生成纪要 → 此刻逐字稿尚**未落库** → 空稿。
///
/// 本文件固化：流式补头后，WAV 字节 = 44B 头 + PCM；头可被 `parseWavDurationMs`
/// 解析且时长 = `pcmBytes` 推导值；同时逐字稿已落库。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/finalize_poller.dart';
import 'package:smart_minutes_flutter/backend/services/session_store.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/backend/storage/audio_archive.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/core/pcm/audio_frame.dart';
import 'package:smart_minutes_flutter/core/pcm/wav.dart';
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
class _Repo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

  @override
  Future<void> saveMeeting(Meeting meeting) async =>
      saved[meeting.id] = meeting;

  @override
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {}

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 捕获归档（记录归档时读到的 WAV 字节，断言其合法性）。
class _CapturingArchive implements AudioArchive {

  @override
  Future<String> putFileAs(String key, String srcPath) async => key;

  @override
  Future<String> pathForKey(String key) async => key;
  Uint8List? captured;

  @override
  String get mode => 'local';

  @override
  Future<String> put(String meetingId, Uint8List wav) async {
    captured = wav;
    return meetingId;
  }

  @override
  Future<String> putFile(String meetingId, String srcPath) async {
    captured = await File(srcPath).readAsBytes();
    return meetingId;
  }

  @override
  Future<Uint8List?> get(String key) async => captured;

  @override
  Future<String> localPath(String key) async => '/tmp/$key.wav';

  @override
  Future<void> remove(String key) async {}
}

/// 假引擎：可控地「产出」实时句子；喂入的 PCM 由转写服务写盘。
class _Engine implements Engine {
  final Map<String, StreamController<StreamEvent>> _controllers =
      <String, StreamController<StreamEvent>>{};

  @override
  String get name => 'fake';

  @override
  Stream<StreamEvent> startRealtimeSession({
    required String sessionId,
    required int sampleRate,
  }) {
    final StreamController<StreamEvent> controller =
        StreamController<StreamEvent>();
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
        speakerId: 'spk_pending',
        text: text,
        startTime: start,
        endTime: end,
        isFinal: true,
        confidence: 0.9,
      ),
    );
  }

  Future<void> closeAll() async {
    for (final StreamController<StreamEvent> controller
        in _controllers.values) {
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const MethodChannel pathProvider = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async {
          if (call.method == 'getTemporaryDirectory' ||
              call.method == 'getApplicationSupportDirectory' ||
              call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.createTempSync('sm_wav_').path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  test('onStop 流式补头：WAV 合法（44B 头 + PCM）且逐字稿先落库', () async {
    final _Repo repo = _Repo();
    final _CapturingArchive archive = _CapturingArchive();
    final _Engine engine = _Engine();
    final SessionStore store = SessionStore();
    final TranscriptionService svc = TranscriptionService(
      engine: engine,
      sessionStore: store,
      persistence: repo,
      archive: archive,
      cfg: AppConfig.defaults(),
    );
    addTearDown(() async {
      await svc.dispose();
      await engine.closeAll();
    });
    repo.saved['m1'] = _meeting('m1');

    await svc.startSession(sessionId: 's1', meetingId: 'm1');
    engine.emitSentence('s1', id: 'seg_1', text: '你好世界', start: 0, end: 1000);

    const int frames = 5;
    for (int i = 0; i < frames; i++) {
      svc.onAudioFrame(
        's1',
        AudioFrame(
          flag: 0,
          seq: i,
          startMs: i * frameMs,
          pcm: Uint8List(frameBytes),
        ),
      );
    }
    await _settle();

    final Meeting? stopped = await svc.onStop(
      'm1',
      upload: true,
      sessionId: 's1',
    );
    expect(stopped, isNotNull);

    // 1) 逐字稿已落库（空稿根因的另一道防线）。
    expect(repo.saved['m1']!.segments.length, 1, reason: '实时句必须在 onStop 落库');
    expect(repo.saved['m1']!.segments.first.text, '你好世界');

    // 2) WAV 是流式补头产出的**合法** WAV：44B 头 + 原始 PCM。
    final Uint8List? wav = archive.captured;
    expect(wav, isNotNull, reason: 'WAV 必须已归档');
    const int pcmBytes = frames * frameBytes;
    expect(wav!.length, kWavHeaderBytes + pcmBytes);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    // 防「头被写到文件尾部」（Android O_APPEND + setPosition(0) 的经典陷阱）：
    // 尾部 44B 绝不能再出现一个 RIFF 头。
    expect(
      String.fromCharCodes(
        wav.sublist(
          wav.length - kWavHeaderBytes,
          wav.length - kWavHeaderBytes + 4,
        ),
      ),
      isNot('RIFF'),
      reason: '头必须在文件开头，而不是被追加到尾部',
    );

    // 3) 头里的时长 = 由 PCM 字节数推导的时长（无需整份解析）。
    expect(
      parseWavDurationMs(wav),
      wavDurationMsFromPcmBytes(pcmBytes, sampleRate: 16000),
    );
    expect(
      parseWavDurationMs(wav),
      100,
      reason: '5×640B @16k/16bit/mono = 100ms',
    );
  });

  test('无音频时 onStop 不产出 WAV（audioKey=null），但流程不崩', () async {
    final _Repo repo = _Repo();
    final _CapturingArchive archive = _CapturingArchive();
    final _Engine engine = _Engine();
    final TranscriptionService svc = TranscriptionService(
      engine: engine,
      sessionStore: SessionStore(),
      persistence: repo,
      archive: archive,
      cfg: AppConfig.defaults(),
    );
    addTearDown(() async {
      await svc.dispose();
      await engine.closeAll();
    });
    repo.saved['m1'] = _meeting('m1');
    await svc.startSession(sessionId: 's1', meetingId: 'm1');

    final Meeting? stopped = await svc.onStop(
      'm1',
      upload: true,
      sessionId: 's1',
    );
    expect(stopped, isNotNull);
    expect(archive.captured, isNull, reason: 'PCM=0B 时不应产出 WAV');
    expect(stopped!.audioKey, isNull);
    expect(
      stopped.finalizeStatus,
      FinalizeStatus.none,
      reason: '无终稿来源时不得落 pending（纪要页门控依赖这个状态区分「等待终稿」与「无终稿链路」）',
    );
  });

  test('onStop 主落库必须同步写入 finalize_status=pending（数据统一门控的前提）', () async {
    final _Repo repo = _Repo();
    final _CapturingArchive archive = _CapturingArchive();
    final _Engine engine = _Engine();
    final SessionStore store = SessionStore();
    final TranscriptionService svc = TranscriptionService(
      engine: engine,
      sessionStore: store,
      persistence: repo,
      archive: archive,
      cfg: AppConfig.defaults(),
    );
    // Noop 轮询器：start 立即返回、不做上传/提交 —— 让 pending 稳定保留供断言。
    svc.finalizePoller = _NoopFinalizePoller(engine: engine, persistence: repo);
    addTearDown(() async {
      await svc.dispose();
      await engine.closeAll();
    });
    repo.saved['m1'] = _meeting('m1');

    await svc.startSession(sessionId: 's1', meetingId: 'm1');
    engine.emitSentence('s1', id: 'seg_1', text: '你好世界', start: 0, end: 1000);
    svc.onAudioFrame(
      's1',
      AudioFrame(flag: 0, seq: 0, startMs: 0, pcm: Uint8List(frameBytes)),
    );
    await _settle();

    final Meeting? stopped = await svc.onStop(
      'm1',
      upload: true,
      sessionId: 's1',
    );
    expect(stopped, isNotNull);
    expect(
      stopped!.finalizeStatus,
      FinalizeStatus.pending,
      reason:
          'pending 必须随 onStop 主落库一起写入 —— '
          '纪要页读到 pending 就会等待终稿，绝不抢跑用实时稿生成纪要（数据统一 2026-09-26）',
    );
    expect(
      repo.saved['m1']!.finalizeStatus,
      FinalizeStatus.pending,
      reason: '库中的快照同样必须是 pending',
    );
  });
}

/// Noop 终稿轮询器：start 立即返回，不触发真实上传 / 提交 / 落盘。
class _NoopFinalizePoller extends FinalizePoller {
  _NoopFinalizePoller({required super.engine, required super.persistence})
    : super(cfg: AppConfig.defaults());

  @override
  Future<String> start(
    String meetingId, {
    required String wavPath,
    bool diarization = true,
  }) async => '';
}
