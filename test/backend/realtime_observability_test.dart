/// P0 可观测性回归：把「音频在收音但没有转写」的**静默失败**变成**显式可诊断**。
///
/// 覆盖三条曾经的「黑洞」：
/// 1. `TranscriptionService.onAudioFrame` 在会话不存在时**静默丢帧** →
///    现在首次告警写日志 + 上报一次 `EngineErrorEvent`（不刷屏）；
/// 2. `BailianEngine` 连接阶段失败（DNS / TLS / 401 / 域名错）只 `logWarn` →
///    现在把 URL 与原因包成可读 `RealtimeFailure` 送到事件流；
/// 3. 握手成功但服务端**既不回 `task-started` 也不报错**（连接被静默关闭同）→
///    现在由启动超时 `kRealtimeStartTimeout` 兜住并上报。
///
/// 另附自检读数（帧数 / 落盘字节 / 已产句子 / 会话是否就绪）的取值校验。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/bailian/bailian_engine.dart';
import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/engine/mock/mock_engine.dart';
import 'package:smart_minutes_flutter/backend/services/session_store.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/backend/storage/audio_archive.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/core/pcm/audio_frame.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';

/// 让事件循环转几圈（流事件 / 多段 await 链靠它收敛）。
Future<void> _settle({int ms = 40}) async {
  for (int i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms ~/ 4));
  }
}

/// 构造一帧 640B 的静音 PCM。
AudioFrame _frame(int seq) =>
    AudioFrame(flag: 0, seq: seq, startMs: seq * frameMs, pcm: Uint8List(frameBytes));

/// 建一个只依赖替身的转写服务。
TranscriptionService _service(Engine engine) => TranscriptionService(
  engine: engine,
  sessionStore: SessionStore(),
  persistence: _FakeRepo(),
  archive: _FakeArchive(),
  cfg: AppConfig.defaults(),
);

void main() {
  // `startSession` 会创建临时 PCM 文件（`getTemporaryDirectory()`），
  // 需初始化 binding 并给 path_provider 一个临时目录替身。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => Directory.systemTemp.path,
    );
  });

  group('P0-1 onAudioFrame：会话不存在不再静默丢帧', () {
    test('未知会话：每会话只告警一次，并上报一条 E_NO_SESSION', () async {
      final _FakeEngine engine = _FakeEngine();
      final TranscriptionService service = _service(engine);
      final List<TranscriptEvent> events = <TranscriptEvent>[];
      final StreamSubscription<TranscriptEvent> sub = service.events.listen(events.add);

      service.onAudioFrame('ghost', _frame(0));
      service.onAudioFrame('ghost', _frame(1));
      service.onAudioFrame('ghost', _frame(2));
      await _settle();

      final List<EngineErrorEvent> errors = events.whereType<EngineErrorEvent>().toList();
      expect(errors, hasLength(1), reason: '同一会话只上报一次，避免刷屏');
      expect(errors.single.code, 'E_NO_SESSION');
      expect(service.lastEngineError, isNotNull);
      expect(engine.fedFrames, 0, reason: '会话不存在时帧确实没被下发，但已被记录');
      expect(service.framesForSession('ghost'), 0);

      await sub.cancel();
      await service.dispose();
    });
  });

  group('P0-1/P1 自检读数：帧 / 字节 / 句子 / 就绪态', () {
    test('正常会话：帧数、落盘字节、句子数与就绪态逐级对齐', () async {
      final _FakeEngine engine = _FakeEngine(running: true, emitSentenceOnFirstFeed: true);
      final TranscriptionService service = _service(engine);
      final StreamSubscription<TranscriptEvent> sub = service.events.listen((_) {});

      await service.startSession(sessionId: 's1', meetingId: 'm1');
      expect(service.isRealtimeRunning('s1'), isTrue, reason: '引擎已就绪应如实反映');

      for (int i = 0; i < 3; i++) {
        service.onAudioFrame('s1', _frame(i));
      }
      await _settle();

      expect(service.framesForSession('s1'), 3);
      expect(service.pcmBytesForSession('s1'), 3 * frameBytes);
      expect(service.framesForSession(null), 0);
      expect(
        service.segmentCountForSession('s1'),
        1,
        reason: '引擎回吐的句子应计入会话逐字稿',
      );
      expect(service.lastEngineError, isNull);
      expect(engine.fedFrames, 3);

      await sub.cancel();
      await service.dispose();
    });
  });

  group('P0-2 连接失败：把 URL 与原因送到事件流', () {
    test('握手抛错（DNS / TLS / 401）→ 事件流收到可读 RealtimeFailure', () async {
      final BailianEngine engine = BailianEngine(
        AppConfig.defaults(),
        socketFactory: (String url, Map<String, dynamic> headers) async {
          throw StateError('Name or service not known');
        },
      );
      final List<Object> errors = <Object>[];
      final StreamSubscription<StreamEvent> sub = engine
          .startRealtimeSession(sessionId: 's', sampleRate: 16000)
          .listen((StreamEvent _) {}, onError: errors.add);
      await _settle();

      expect(errors, hasLength(1), reason: '连接失败必须上报，不能只有 logWarn');
      final String text = errors.single.toString();
      expect(text, contains('连接失败'));
      expect(text, contains('wss://'), reason: '必须带 WS URL 才能定位域名 / 地域问题');
      expect(text, contains('Name or service not known'));

      await sub.cancel();
      engine.abortRealtimeSession('s');
      await engine.dispose();
    });
  });

  group('P0-2 启动超时：握手成功但服务端静默', () {
    test('迟迟不返回 task-started → 超时后上报「连接超时」并中止', () async {
      final _SilentSocket socket = _SilentSocket();
      final List<Object> errors = <Object>[];
      final BailianRealtimeSession session = BailianRealtimeSession(
        cfg: AppConfig.defaults(),
        sessionId: 's',
        meetingId: 'm',
        onEvent: (_) {},
        onError: errors.add,
        socketFactory: (String url, Map<String, dynamic> headers) async => socket,
        startTimeout: const Duration(milliseconds: 80),
      );

      await session.open();
      // 服务端此时没有任何回包：先确认还没有误报。
      expect(errors, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await _settle();

      expect(errors, hasLength(1), reason: '静默不响应必须由启动超时兜住');
      expect(errors.single.toString(), contains('连接超时'));
      expect(session.lastError, isNotNull);

      session.close();
    });

    test('服务端立即回 task-failed → 上报可读原因（不再是纯代码）', () async {
      final _TaskFailedSocket socket = _TaskFailedSocket(
        code: 'InvalidParameter',
        message: 'model not exist',
      );
      final List<Object> errors = <Object>[];
      final BailianRealtimeSession session = BailianRealtimeSession(
        cfg: AppConfig.defaults(),
        sessionId: 's',
        meetingId: 'm',
        onEvent: (_) {},
        onError: errors.add,
        maxRestart: 0, // 不重试，直接暴露服务端原因
        socketFactory: (String url, Map<String, dynamic> headers) async => socket,
        startTimeout: const Duration(milliseconds: 500),
      );

      await session.open();
      await _settle(ms: 80);

      expect(errors, isNotEmpty);
      final String text = errors.first.toString();
      expect(text, contains('实时转写暂不可用'));
      expect(text, contains('model not exist'), reason: '服务端 error_message 必须透出');
      expect(text, contains('InvalidParameter'));

      session.close();
    });
  });

  group('P1 引擎就绪态：Mock 引擎', () {
    test('Mock 会话开启后 running=true，停止后 false', () async {
      final MockEngine engine = MockEngine();
      engine.startRealtimeSession(sessionId: 's', sampleRate: 16000);
      expect(engine.isRealtimeRunning('s'), isTrue);
      await engine.stopRealtimeSession('s');
      expect(engine.isRealtimeRunning('s'), isFalse);
      await engine.dispose();
    });
  });
}

/// 可控假引擎：可指定是否就绪、是否在首次收到音频时回吐一句。
class _FakeEngine implements Engine {
  _FakeEngine({this.running = false, this.emitSentenceOnFirstFeed = false});

  final bool running;
  final bool emitSentenceOnFirstFeed;

  int fedFrames = 0;
  StreamController<StreamEvent>? _controller;

  @override
  String get name => 'fake';

  @override
  Stream<StreamEvent> startRealtimeSession({required String sessionId, required int sampleRate}) {
    final StreamController<StreamEvent> controller = StreamController<StreamEvent>.broadcast();
    _controller = controller;
    return controller.stream;
  }

  @override
  bool isRealtimeRunning(String sessionId) => running;

  @override
  bool feedRealtime(String sessionId, Uint8List pcm16le) {
    fedFrames++;
    if (emitSentenceOnFirstFeed && fedFrames == 1) {
      _controller?.add(
        const StreamEvent(
          segmentId: 'seg_1',
          speakerId: kPendingSpeakerId,
          text: '第一句',
          startTime: 0,
          endTime: 1000,
          isFinal: true,
          confidence: 0.9,
          revision: 1,
        ),
      );
    }
    return running;
  }

  @override
  Future<void> stopRealtimeSession(String sessionId) async {
    await _controller?.close();
    _controller = null;
  }

  @override
  void abortRealtimeSession(String sessionId) {
    unawaited(_controller?.close());
    _controller = null;
  }

  @override
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true}) async => 't';

  @override
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval}) async =>
      const FiletransResult(status: 'FAILED', segments: <TranscriptSegment>[]);

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) =>
      const Stream<String>.empty();

  @override
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) async => '';

  @override
  Future<void> dispose() async {
    await _controller?.close();
    _controller = null;
  }
}

/// 永不回包的假 WS（模拟「握手成功但服务端静默」）。
class _SilentSocket implements RealtimeSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>.broadcast();

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  void sendText(String text) {}

  @override
  void sendBytes(Uint8List bytes) {}

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// 收到 run-task 后立即回 `task-failed` 的假 WS。
class _TaskFailedSocket implements RealtimeSocket {
  _TaskFailedSocket({required this.code, required this.message});

  final String code;
  final String message;
  final StreamController<Object?> _incoming = StreamController<Object?>.broadcast();

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  void sendText(String text) {
    // 只对 run-task 作出反应。
    if (text.contains('run-task')) {
      scheduleMicrotask(() {
        if (_incoming.isClosed) return;
        _incoming.add(
          jsonEncode(<String, dynamic>{
            'header': <String, dynamic>{
              'event': 'task-failed',
              'error_code': code,
              'error_message': message,
            },
          }),
        );
      });
    }
  }

  @override
  void sendBytes(Uint8List bytes) {}

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// 最小内存仓储（转写服务只用到会议读写）。
class _FakeRepo implements MeetingRepository {
  final Map<String, Meeting> _saved = <String, Meeting>{};

  @override
  Future<Meeting?> loadMeeting(String id) async => _saved[id];

  @override
  Future<void> saveMeeting(Meeting meeting) async => _saved[meeting.id] = meeting;

  @override
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {
    final Meeting? m = _saved[id];
    if (m == null) return;
    _saved[id] = m.copyWith(
      minutesMd: minutesMd,
      status: status,
      minutesPartial: minutesPartial,
      minutesError: minutesError,
    );
  }
  @override
  Future<void> saveFiletransRaw(String meetingId, String json) async {}

  @override
  Future<String?> loadFiletransRaw(String meetingId) async => null;

  @override
  Future<List<MeetingSummary>> listMeetings() async =>
      _saved.values.map((Meeting m) => m.toSummary()).toList(growable: false);

  @override
  Future<void> deleteMeeting(String id) async => _saved.remove(id);

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

/// 内存归档（转写服务不触盘时用）。
class _FakeArchive implements AudioArchive {
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  @override
  String get mode => 'local';

  @override
  Future<String> put(String meetingId, Uint8List wav) async {
    _files[meetingId] = wav;
    return meetingId;
  }

  @override
  Future<Uint8List?> get(String key) async => _files[key];

  @override
  Future<String> localPath(String key) async => '/tmp/$key.wav';

  @override
  Future<void> remove(String key) async => _files.remove(key);
}
