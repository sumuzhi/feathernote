/// `TranscriptionService.retryFinalize` 回归：终稿失败后的重试链路。
///
/// 固化四个行为：
/// 1. failed + 归档在 → 复用归档 WAV 重新提交（引擎被调用一次），先回 `pending`
///    再按引擎结果落 `failed`（引擎直接拒绝的非重试错误）；
/// 2. 状态非 failed → 拒绝且**不**触碰引擎；
/// 3. `audioKey` 缺失 → 拒绝且不触碰引擎；
/// 4. 归档路径解析失败（文件丢失）→ 同步抛出、不触发链路。
library;

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
import 'package:smart_minutes_flutter/core/error/app_error.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

/// 让 poller 的后台 Future 收敛。
Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Meeting _meeting(
  String id, {
  FinalizeStatus finalize = FinalizeStatus.failed,
  String? finalizeError = 'AppError(engineError E_TASK_FAILED): 旧失败',
  String? audioKey = 'm1',
}) => Meeting(
  id: id,
  title: '重试测试会议',
  createdAt: DateTime(2026, 9, 28, 10),
  durationMs: 3000,
  sampleRate: 16000,
  speakerCount: 1,
  status: MeetingStatus.stopped,
  source: MeetingSource.microphone,
  finalizeStatus: finalize,
  transcriptSource: TranscriptSource.realtime,
  finalizeError: finalizeError,
  audioStatus: audioKey == null ? AudioStatus.none : AudioStatus.done,
  audioKey: audioKey,
  audioBytes: 1024,
  minutesPartial: false,
  segments: const <TranscriptSegment>[],
  speakers: const <Speaker>[],
);

class _Repo implements MeetingRepository {
  final Map<String, Meeting> saved = <String, Meeting>{};

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
  }) async {}

  @override
  Future<Meeting?> loadMeeting(String id) async => saved[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Archive implements AudioArchive {
  /// 非 null 时 [localPath] 返回该已存在文件；null 时抛错（模拟归档丢失）。
  String? existingPath;

  @override
  String get mode => 'local';

  @override
  Future<String> put(String meetingId, List<int> wav) async => meetingId;

  @override
  Future<String> putFile(String meetingId, String srcPath) async => meetingId;

  @override
  Future<Uint8List?> get(String key) async => null;

  @override
  Future<String> localPath(String key) async {
    final String? path = existingPath;
    if (path == null) {
      throw StateError('归档条目不存在：$key');
    }
    return path;
  }

  @override
  Future<void> remove(String key) async {}
}

/// 假引擎：统计 filetrans 提交次数，可配置为直接抛非重试错误。
class _Engine implements Engine {
  int submitCalls = 0;
  Object? submitError;

  @override
  Future<String> submitFiletrans({
    required String wavPathOrUrl,
    bool diarization = true,
  }) async {
    submitCalls++;
    final Object? error = submitError;
    if (error != null) throw error;
    return 'task-1';
  }

  @override
  String get name => 'fake';

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
            return Directory.systemTemp.createTempSync('sm_retry_').path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  TranscriptionService boot(
    _Repo repo,
    _Archive archive,
    _Engine engine,
  ) {
    final SessionStore store = SessionStore();
    final AppConfig cfg = AppConfig.defaults();
    final TranscriptionService svc = TranscriptionService(
      engine: engine,
      sessionStore: store,
      persistence: repo,
      archive: archive,
      cfg: cfg,
    );
    svc.attachFinalizePoller(
      FinalizePoller(engine: engine, persistence: repo, cfg: cfg),
    );
    return svc;
  }

  test('重试：复用归档 WAV 重新提交；先回 pending 再按结果落 failed', () async {
    final _Repo repo = _Repo();
    final _Archive archive = _Archive();
    final File wav = File(
      '${Directory.systemTemp.createTempSync('sm_retry_wav_').path}/m1.wav',
    )..writeAsBytesSync(List<int>.filled(64, 1));
    archive.existingPath = wav.path;
    final _Engine engine = _Engine()
      ..submitError = const AppError(
        ErrorCode.engineError,
        'filetrans 未成功（status=failed）',
        engineCode: 'E_TASK_FAILED',
      );
    final TranscriptionService svc = boot(repo, archive, engine);
    repo.saved['m1'] = _meeting('m1');

    await svc.retryFinalize('m1'); // startFinalize 契约在 pending 落盘后即返回
    await _settle();

    expect(engine.submitCalls, 1, reason: '重试必须真正重新提交');
    final Meeting m = repo.saved['m1']!;
    expect(m.finalizeStatus, FinalizeStatus.failed, reason: '引擎直接拒绝 → 再落 failed');
    expect(m.finalizeError, contains('filetrans 未成功'), reason: '落库保留原始错误');
  });

  test('重试前置：状态非 failed 直接拒绝且不触碰引擎', () async {
    final _Repo repo = _Repo();
    final _Archive archive = _Archive()..existingPath = '/tmp/x.wav';
    final _Engine engine = _Engine();
    final TranscriptionService svc = boot(repo, archive, engine);
    repo.saved['m1'] = _meeting('m1', finalize: FinalizeStatus.done);

    await expectLater(svc.retryFinalize('m1'), throwsA(isA<AppError>()));
    expect(engine.submitCalls, 0);
  });

  test('重试前置：audioKey 缺失拒绝且不触碰引擎', () async {
    final _Repo repo = _Repo();
    final _Archive archive = _Archive()..existingPath = '/tmp/x.wav';
    final _Engine engine = _Engine();
    final TranscriptionService svc = boot(repo, archive, engine);
    repo.saved['m1'] = _meeting('m1', audioKey: null);

    await expectLater(svc.retryFinalize('m1'), throwsA(isA<AppError>()));
    expect(engine.submitCalls, 0);
  });

  test('重试：归档文件丢失 → 同步抛错且不触发链路', () async {
    final _Repo repo = _Repo();
    final _Archive archive = _Archive()..existingPath = null; // localPath 抛错
    final _Engine engine = _Engine();
    final TranscriptionService svc = boot(repo, archive, engine);
    repo.saved['m1'] = _meeting('m1');

    await expectLater(
      svc.retryFinalize('m1'),
      throwsA(
        isA<AppError>().having(
          (AppError e) => e.message,
          'message',
          contains('录音文件已丢失'),
        ),
      ),
    );
    expect(engine.submitCalls, 0);
  });
}
