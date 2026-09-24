/// 转写编排服务：实时（百炼 → `spk_pending` 上屏）+ 停止落库 + 终稿链路触发。
///
/// 移植 `server/src/services/transcriptionService.js`，并把原「WS 网关下发」
/// 替换为 [TranscriptEvent] 事件广播（方案 B 无 WS 传输层）。
///
/// **U6 改道**：2 小时录音（~230MB）不整份驻留内存 —— 录音期间 PCM **边录边追加写**
/// 临时文件（`IOSink`），停止时只写 WAV 头。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/ids.dart';
import '../../core/log/log.dart';
import '../../core/pcm/audio_frame.dart';
import '../../core/pcm/wav.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../algo/chunk_store.dart';
import '../algo/clustering.dart';
import '../engine/engine.dart';
import '../storage/audio_archive.dart';
import '../storage/meeting_repository.dart';
import 'finalize_poller.dart';
import 'session_store.dart';

/// 停止时等待实时任务收尾的最长时间（毫秒），避免 `/stop` 长时间挂起。
const int kFlushTimeoutMs = 3000;

/// 对外事件（UI / debug 适配层订阅），替代原 `AudioGateway` 的 WS 下发。
sealed class TranscriptEvent {}

/// 实时逐字稿增量。
class TranscriptUpsert extends TranscriptEvent {
  /// 构造事件。
  TranscriptUpsert({required this.sessionId, required this.meetingId, required this.event});

  /// 会话 ID。
  final String sessionId;

  /// 会议 ID。
  final String meetingId;

  /// 实时事件。
  final StreamEvent event;
}

/// 终稿全量替换逐字稿。
class TranscriptReplace extends TranscriptEvent {
  /// 构造事件。
  TranscriptReplace({required this.meetingId, required this.segments, required this.speakers});

  /// 会议 ID。
  final String meetingId;

  /// 终稿片段。
  final List<TranscriptSegment> segments;

  /// 说话人表。
  final List<Speaker> speakers;
}

/// 会议已建立。
class MeetingStarted extends TranscriptEvent {
  /// 构造事件。
  MeetingStarted({required this.meetingId, required this.sessionId});

  /// 会议 ID。
  final String meetingId;

  /// 会话 ID。
  final String sessionId;
}

/// 会议已停止。
class MeetingStopped extends TranscriptEvent {
  /// 构造事件。
  MeetingStopped({required this.meetingId, required this.speakerCount, required this.durationMs});

  /// 会议 ID。
  final String meetingId;

  /// 说话人数量。
  final int speakerCount;

  /// 时长（毫秒）。
  final int durationMs;
}

/// 说话人表更新。
class SpeakerUpdate extends TranscriptEvent {
  /// 构造事件。
  SpeakerUpdate({required this.meetingId, required this.speakers});

  /// 会议 ID。
  final String meetingId;

  /// 说话人表。
  final List<Speaker> speakers;
}

/// 终稿状态变化。
class FinalizeProgress extends TranscriptEvent {
  /// 构造事件。
  FinalizeProgress({required this.meetingId, required this.status, this.taskId, this.error});

  /// 会议 ID。
  final String meetingId;

  /// 终稿状态（`pending` / `done` / `failed`）。
  final String status;

  /// 百炼任务 ID。
  final String? taskId;

  /// 失败原因。
  final String? error;
}

/// 引擎错误。
class EngineErrorEvent extends TranscriptEvent {
  /// 构造事件。
  EngineErrorEvent({required this.code, required this.message});

  /// 错误码。
  final String code;

  /// 中文提示。
  final String message;
}

/// 转写编排服务。
class TranscriptionService {
  /// 构造服务。
  TranscriptionService({
    required this.engine,
    required this.sessionStore,
    required this.persistence,
    required this.archive,
    required this.cfg,
    this.finalizePoller,
  });

  /// 引擎。
  final Engine engine;

  /// 会话态存储。
  final SessionStore sessionStore;

  /// 持久化门面。
  final MeetingRepository persistence;

  /// 音频归档。
  final AudioArchive archive;

  /// 冻结配置。
  final AppConfig cfg;

  /// 终稿轮询器（可后置注入）。
  FinalizePoller? finalizePoller;

  final StreamController<TranscriptEvent> _events = StreamController<TranscriptEvent>.broadcast();
  final Map<String, _SessionRuntime> _runtimes = <String, _SessionRuntime>{};

  /// 对外事件流（UI / debug 适配层订阅）。
  Stream<TranscriptEvent> get events => _events.stream;

  /// 后置注入终稿轮询器。
  void attachFinalizePoller(FinalizePoller poller) => finalizePoller = poller;

  /// 开启实时会话：建立引擎会话并订阅事件。
  Future<SessionState> startSession({
    required String sessionId,
    required String meetingId,
    String? title,
    int? startedAtMs,
    int sampleRate = 16000,
  }) async {
    final SessionState state = sessionStore.getOrCreate(
      sessionId,
      meetingId: meetingId,
      title: title ?? '',
      startedAtMs: startedAtMs,
      sampleRate: sampleRate,
    );
    final _SessionRuntime runtime = await _SessionRuntime.open(meetingId);
    _runtimes[sessionId] = runtime;

    final StreamSubscription<StreamEvent> subscription = engine
        .startRealtimeSession(sessionId: sessionId, sampleRate: sampleRate)
        .listen(
          (StreamEvent event) => _handleRealtimeEvent(sessionId, meetingId, event),
          onError: (Object error) {
            logWarn('transcription', '实时引擎错误 session=$sessionId：$error');
            _emit(
              EngineErrorEvent(code: 'E_ENGINE', message: error.toString()),
            );
          },
        );
    runtime.subscription = subscription;
    _emit(MeetingStarted(meetingId: meetingId, sessionId: sessionId));
    logInfo('transcription', '实时会话已开启 session=$sessionId meeting=$meetingId');
    return state;
  }

  void _handleRealtimeEvent(String sessionId, String meetingId, StreamEvent event) {
    final SessionState? state = sessionStore.get(sessionId);
    if (state != null) {
      state.tracker.accept(event.startTime ~/ 20, event.startTime, event.endTime);
    }
    sessionStore.upsertSegment(sessionId, event);
    _emit(TranscriptUpsert(sessionId: sessionId, meetingId: meetingId, event: event));
  }

  /// 上送一帧音频。
  void onAudioFrame(String sessionId, AudioFrame frame) {
    final _SessionRuntime? runtime = _runtimes[sessionId];
    if (runtime == null) return;
    // U6：边录边追加写，不整份驻留内存。
    runtime.sink.add(frame.pcm);
    runtime.pcmBytes += frame.pcm.length;
    final SessionState? state = sessionStore.get(sessionId);
    if (state != null) {
      state.tracker.accept(frame.seq, frame.startMs, frame.endMs);
    }
    engine.feedRealtime(sessionId, frame.pcm);
  }

  /// 关闭实时会话（可先 flush 收尾）。
  Future<void> closeSession(String sessionId, {bool flush = false}) async {
    final _SessionRuntime? runtime = _runtimes.remove(sessionId);
    if (runtime == null) return;
    if (flush) {
      try {
        await engine.stopRealtimeSession(sessionId).timeout(const Duration(milliseconds: kFlushTimeoutMs));
      } catch (error) {
        logWarn('transcription', '实时收尾失败 session=$sessionId：$error');
      }
    } else {
      engine.abortRealtimeSession(sessionId);
    }
    await runtime.subscription?.cancel();
    await runtime.close();
  }

  /// 停止会议：收尾实时会话 → 写 WAV → 归档 → 落库 → 提交终稿。
  Future<Meeting?> onStop(String meetingId, {bool upload = true}) async {
    final Meeting? stored = await persistence.loadMeeting(meetingId);
    if (stored == null) return null;

    final SessionState? state = sessionStore.findByMeeting(meetingId);
    final String? sessionId = state?.sessionId;
    _SessionRuntime? runtime = sessionId == null ? null : _runtimes[sessionId];
    if (sessionId != null) {
      await closeSession(sessionId, flush: true);
      sessionStore.markStopped(sessionId);
    }

    // 1) 汇总逐字稿（会话态优先，其次库中已有）。
    List<TranscriptSegment> segments =
        sessionId != null ? sessionStore.transcript(sessionId) : <TranscriptSegment>[];
    if (segments.isEmpty) segments = stored.segments;
    final List<TranscriptSegment> normalized =
        segments.map(normalizeSegment).toList(growable: false);

    // 2) 写 WAV（流式写已在进行，此处补头）→ 归档。
    int durationMs = deriveDurationMs(normalized.map((TranscriptSegment s) => s.endTime));
    String? audioKey;
    if (runtime != null) {
      final Uint8List wav = await runtime.finishWav(sampleRate: stored.sampleRate);
      if (wav.isNotEmpty) {
        final int wavMs = parseWavDurationMs(wav) ?? 0;
        if (wavMs > durationMs) durationMs = wavMs;
        if (upload) {
          audioKey = await archive.put(meetingId, wav);
        }
      }
    }

    final List<Speaker> roster = buildSpeakerRoster(normalized, meetingId: meetingId);
    final Meeting updated = stored.copyWith(
      segments: normalized,
      durationMs: durationMs > 0 ? durationMs : stored.durationMs,
      status: MeetingStatus.stopped,
      speakers: roster,
      speakerCount: roster.length,
      audioStatus: audioKey == null ? AudioStatus.none : AudioStatus.done,
      audioKey: audioKey,
      audioBytes: runtime?.pcmBytes ?? 0,
    );
    await persistence.saveMeeting(updated);
    _emit(
      MeetingStopped(meetingId: meetingId, speakerCount: roster.length, durationMs: updated.durationMs),
    );
    if (roster.isNotEmpty) {
      _emit(SpeakerUpdate(meetingId: meetingId, speakers: roster));
    }
    logInfo(
      'transcription',
      '会议已停止 meeting=$meetingId 片段=${normalized.length} 时长=${updated.durationMs}ms',
    );

    // 3) 触发终稿链路（失败不影响停止流程本身）。
    if (upload && audioKey != null) {
      final String? wavPath = await _resolveArchivePath(audioKey);
      if (wavPath != null) {
        await startFinalize(meetingId, wavPath: wavPath);
      }
    }
    return updated;
  }

  /// 触发终稿转写链路（委托 [FinalizePoller]）。
  Future<void> startFinalize(String meetingId, {required String wavPath, bool diarization = true}) async {
    final FinalizePoller? poller = finalizePoller;
    if (poller == null) throw AppError(ErrorCode.internal, 'finalizePoller 未装配');
    await poller.start(meetingId, wavPath: wavPath, diarization: diarization);
  }

  /// 终稿完成回调（由 [FinalizePoller] 调用）：**先落库再广播**。
  Future<void> handleFinalizeComplete(String meetingId, List<TranscriptSegment> segments) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting != null) {
      final List<TranscriptSegment> normalized =
          segments.map(normalizeSegment).toList(growable: false);
      final List<Speaker> roster = buildSpeakerRoster(normalized, meetingId: meetingId);
      await persistence.saveMeeting(
        meeting.copyWith(
          segments: normalized,
          speakers: roster,
          speakerCount: roster.length,
          finalizeStatus: FinalizeStatus.done,
          transcriptSource: TranscriptSource.filetrans,
        ),
      );
      _emit(TranscriptReplace(meetingId: meetingId, segments: normalized, speakers: roster));
      _emit(SpeakerUpdate(meetingId: meetingId, speakers: roster));
    }
    final SessionState? state = sessionStore.findByMeeting(meetingId);
    if (state != null) {
      sessionStore.replaceTranscript(state.sessionId, segments);
    }
  }

  /// 广播终稿进度。
  void emitFinalizeProgress(String meetingId, String status, {String? taskId, String? error}) {
    _emit(
      FinalizeProgress(meetingId: meetingId, status: status, taskId: taskId, error: error),
    );
  }

  Future<String?> _resolveArchivePath(String key) async {
    try {
      return await archive.localPath(key);
    } catch (error) {
      logWarn('transcription', '解析归档路径失败 key=$key：$error');
      return null;
    }
  }

  void _emit(TranscriptEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// 释放资源。
  Future<void> dispose() async {
    for (final String sessionId in _runtimes.keys.toList(growable: false)) {
      await closeSession(sessionId);
    }
    await _events.close();
  }
}

/// 会话运行态：临时 PCM 文件写入器（U6：边录边追加写）。
class _SessionRuntime {
  /// 私有构造。
  _SessionRuntime._(this._file, this._sink);

  /// 打开临时文件（流式写入）。
  static Future<_SessionRuntime> open(String meetingId) async {
    final Directory tmp = await getTemporaryDirectory();
    final Directory dir = Directory(p.join(tmp.path, 'smart-minutes-pcm'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File(p.join(dir.path, '$meetingId.pcm'));
    final IOSink sink = file.openWrite(mode: FileMode.writeOnly);
    return _SessionRuntime._(file, sink);
  }

  final File _file;
  final IOSink _sink;

  /// 实时事件订阅。
  StreamSubscription<StreamEvent>? subscription;

  /// 已写入的 PCM 字节数。
  int pcmBytes = 0;

  /// PCM 写入器。
  IOSink get sink => _sink;

  /// 收尾：flush + 读回 PCM → 组装 WAV。
  Future<Uint8List> finishWav({required int sampleRate}) async {
    try {
      await _sink.flush();
      await _sink.close();
    } catch (error) {
      logWarn('transcription', 'PCM 落盘 flush 失败：$error');
    }
    if (pcmBytes == 0) return Uint8List(0);
    final Uint8List pcm = await _file.readAsBytes();
    return buildWav(pcm16le: pcm, sampleRate: sampleRate);
  }

  /// 关闭并清理临时文件。
  Future<void> close() async {
    try {
      await _sink.close();
    } catch (_) {
      // 忽略关闭异常。
    }
  }
}

/// 帧序号追踪器（供外部断言「无丢帧」）。
ChunkTracker trackerOf(SessionState state) => state.tracker;
