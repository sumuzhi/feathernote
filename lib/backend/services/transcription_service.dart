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

  /// 「会话不存在导致丢帧」的已告警会话集合（每个会话只告警一次，防刷屏）。
  final Set<String> _missingRuntimeWarned = <String>{};

  /// 最近一次引擎错误（供自检面板展示；无错误为 null）。
  String? _lastEngineError;

  /// 对外事件流（UI / debug 适配层订阅）。
  Stream<TranscriptEvent> get events => _events.stream;

  /// 最近一次引擎错误文案（自检用；无错误返回 null）。
  String? get lastEngineError => _lastEngineError;

  /// 指定会话的实时识别是否已「就绪」（收到 `task-started`）。
  ///
  /// 这是区分「音频没到后端」与「到了但会话没连上」的关键读数。
  bool isRealtimeRunning(String? sessionId) =>
      sessionId == null ? false : engine.isRealtimeRunning(sessionId);

  /// 指定会话后端实际收到的音频帧数（诊断用；会话不存在返回 0）。
  int framesForSession(String? sessionId) =>
      sessionId == null ? 0 : (_runtimes[sessionId]?.frameCount ?? 0);

  /// 指定会话已产出的实时句子数（诊断用；会话不存在返回 0）。
  int segmentCountForSession(String? sessionId) =>
      sessionId == null ? 0 : (sessionStore.get(sessionId)?.segments.length ?? 0);

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
    _missingRuntimeWarned.remove(sessionId);
    _lastEngineError = null;

    final StreamSubscription<StreamEvent> subscription = engine
        .startRealtimeSession(sessionId: sessionId, sampleRate: sampleRate)
        .listen(
          (StreamEvent event) => _handleRealtimeEvent(sessionId, meetingId, event),
          onError: (Object error) {
            logWarn('transcription', '实时引擎错误 session=$sessionId：$error');
            _lastEngineError = error.toString();
            _emit(
              EngineErrorEvent(code: 'E_ENGINE', message: error.toString()),
            );
          },
        );
    runtime.subscription = subscription;
    _emit(MeetingStarted(meetingId: meetingId, sessionId: sessionId));
    logInfo(
      'transcription',
      '实时会话已开启 session=$sessionId meeting=$meetingId engine=${engine.name} '
      'sampleRate=$sampleRate 事件订阅已挂载',
    );
    return state;
  }

  void _handleRealtimeEvent(String sessionId, String meetingId, StreamEvent event) {
    // 历史 Bug 观测点：若这里 `get` 返回 null（会话态被清空 / 未建立），旧实现
    // 只对 tracker 跳过、但**仍把事件上屏** → 出现「UI 有、落库无」。
    // 现在：缺失即**自动重建**（带 meetingId），并告警一次，保证事件一定入库。
    if (sessionStore.get(sessionId) == null) {
      logWarn(
        'transcription',
        '实时事件到达时会话态缺失，已自动重建 session=$sessionId meeting=$meetingId'
        '（此前已上屏但未入库的句子会丢失，请关注是否发生过会话被清理）',
      );
    }
    final SessionState state = sessionStore.getOrCreate(sessionId, meetingId: meetingId);
    state.tracker.accept(event.startTime ~/ 20, event.startTime, event.endTime);
    final TranscriptSegment? stored = sessionStore.upsertSegment(sessionId, event);
    if (stored == null) {
      logWarn(
        'transcription',
        '实时事件未能落会话态（segmentId 为空？）session=$sessionId event=$event',
      );
    }
    _emit(TranscriptUpsert(sessionId: sessionId, meetingId: meetingId, event: event));
  }

  /// 上送一帧音频。
  void onAudioFrame(String sessionId, AudioFrame frame) {
    final _SessionRuntime? runtime = _runtimes[sessionId];
    if (runtime == null) {
      // 历史 Bug：这里曾 `return` 吃掉帧且**不留任何痕迹**，导致「麦克风在响、
      // 波形在动（波形由本地 PCM 驱动），但后端一句都没有」难以定位。
      // 现在：首次告警写日志并上报一次 UI 错误，之后的同会话重复帧只写 debug。
      if (_missingRuntimeWarned.add(sessionId)) {
        final String message = '实时会话未建立，音频未上送（session=$sessionId）';
        logWarn('transcription', '$message：帧已丢弃（同会话后续不再重复告警）');
        _lastEngineError = message;
        _emit(EngineErrorEvent(code: 'E_NO_SESSION', message: message));
      } else {
        logDebug('transcription', '会话不存在，继续丢弃音频帧 session=$sessionId');
      }
      return;
    }
    if (runtime.frameCount == 0) {
      // 每个会话只打一次：确认「Dart 侧上送的帧」真的到了后端。
      logInfo(
        'transcription',
        '后端收到首帧 session=$sessionId seq=${frame.seq} startMs=${frame.startMs} ${frame.pcm.length}B',
      );
      runtime.lastReportAtMs = DateTime.now().millisecondsSinceEpoch;
    }
    // U6：边录边追加写，不整份驻留内存。
    runtime.sink.add(frame.pcm);
    runtime.pcmBytes += frame.pcm.length;
    runtime.frameCount += 1;
    // 每 5 秒汇总一条（既能看到持续收帧，又不刷屏）。
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - runtime.lastReportAtMs >= 5000) {
      runtime.lastReportAtMs = nowMs;
      logInfo(
        'transcription',
        '音频汇总 session=$sessionId 帧=${runtime.frameCount} PCM=${runtime.pcmBytes}B '
        '实时会话=${engine.isRealtimeRunning(sessionId) ? '已连接' : '未连接'}',
      );
    }
    final SessionState? state = sessionStore.get(sessionId);
    if (state != null) {
      state.tracker.accept(frame.seq, frame.startMs, frame.endMs);
    }
    engine.feedRealtime(sessionId, frame.pcm);
  }

  /// 指定会话已落盘的 PCM 字节数（诊断用；会话不存在返回 0）。
  int pcmBytesForSession(String? sessionId) =>
      sessionId == null ? 0 : (_runtimes[sessionId]?.pcmBytes ?? 0);

  /// 关闭实时会话（可先 flush 收尾）。
  Future<void> closeSession(String sessionId, {bool flush = false}) async {
    final _SessionRuntime? runtime = _runtimes.remove(sessionId);
    _missingRuntimeWarned.remove(sessionId);
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
  ///
  /// [sessionId] 可选：起录时绑定的活动会话。传入即**不再依赖 `findByMeeting`
  /// 反查**，从根本上消除「会话存在但反查不到 → 逐字稿为空」的一整类缺陷。
  Future<Meeting?> onStop(String meetingId, {bool upload = true, String? sessionId}) async {
    final Stopwatch watch = Stopwatch()..start();
    final Meeting? stored = await persistence.loadMeeting(meetingId);
    if (stored == null) {
      logWarn('transcription', 'onStop：会议不存在 meeting=$meetingId');
      return null;
    }

    // 会话定位：优先用调用方显式传入的 sessionId（= 起录时绑定的活动会话），
    // 退化才用 findByMeeting 反查。并打印**决定性诊断**：让「空稿」一眼可判。
    final SessionState? byMeeting = sessionStore.findByMeeting(meetingId);
    final String? resolvedSessionId = sessionId ?? byMeeting?.sessionId;
    final SessionState? state =
        resolvedSessionId == null ? null : sessionStore.get(resolvedSessionId);
    final String? activeSessionId = state?.sessionId;
    final _SessionRuntime? runtime =
        activeSessionId == null ? null : _runtimes[activeSessionId];
    // 收尾前采样（closeSession 之后这些读数就没了）。
    final bool realtimeRunning = isRealtimeRunning(activeSessionId);
    final int realtimeSentences = segmentCountForSession(activeSessionId);
    logInfo(
      'transcription',
      'onStop·会话定位 meeting=$meetingId 传入session=${sessionId ?? '—'} '
      '命中session=${activeSessionId ?? '—'} storeMeeting=${state?.meetingId ?? '—'} '
      'storeSegments=${state?.segments.length ?? 0} '
      'findByMeeting=${byMeeting == null ? '未命中' : '命中'}',
    );
    if (activeSessionId != null) {
      logInfo('transcription', 'onStop·收尾实时会话 session=$activeSessionId flush=true');
      await closeSession(activeSessionId, flush: true);
      sessionStore.markStopped(activeSessionId);
      logInfo(
        'transcription',
        'onStop·实时会话已关闭 耗时=${watch.elapsedMilliseconds}ms',
      );
    } else {
      logWarn('transcription', 'onStop：未找到会话态 meeting=$meetingId（实时稿将为空）');
    }

    // 1) 汇总逐字稿（会话态优先，其次库中已有）。
    List<TranscriptSegment> segments = activeSessionId != null
        ? sessionStore.transcript(activeSessionId)
        : <TranscriptSegment>[];
    if (segments.isEmpty) segments = stored.segments;
    final List<TranscriptSegment> normalized =
        segments.map(normalizeSegment).toList(growable: false);
    logInfo(
      'transcription',
      'onStop·逐字稿汇总 segment=${normalized.length} 耗时=${watch.elapsedMilliseconds}ms',
    );

    // 2) 写 WAV（流式写已在进行，此处补头）→ 归档。
    int durationMs = deriveDurationMs(normalized.map((TranscriptSegment s) => s.endTime));
    String? audioKey;
    int wavBytes = 0;
    if (runtime != null) {
      final Uint8List wav = await runtime.finishWav(sampleRate: stored.sampleRate);
      wavBytes = wav.length;
      logInfo(
        'transcription',
        'onStop·WAV 收尾 WAV=${wav.length}B 解析时长=${parseWavDurationMs(wav) ?? 0}ms '
        'PCM=${runtime.pcmBytes}B 帧=${runtime.frameCount}',
      );
      if (wav.isNotEmpty) {
        final int wavMs = parseWavDurationMs(wav) ?? 0;
        if (wavMs > durationMs) durationMs = wavMs;
        if (upload) {
          audioKey = await archive.put(meetingId, wav);
          logInfo('transcription', 'onStop·WAV 已归档 key=$audioKey 耗时=${watch.elapsedMilliseconds}ms');
        }
      } else {
        logWarn('transcription', 'onStop：WAV 为空（PCM=0B，录音未产出数据）');
      }
    } else {
      logWarn('transcription', 'onStop：无 runtime，未产出 WAV（录音未成功建立）');
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
    logInfo(
      'transcription',
      'onStop·已落库 meeting=$meetingId segment=${normalized.length} '
      '说话人=${roster.length} 耗时=${watch.elapsedMilliseconds}ms',
    );
    _emit(
      MeetingStopped(meetingId: meetingId, speakerCount: roster.length, durationMs: updated.durationMs),
    );
    if (roster.isNotEmpty) {
      _emit(SpeakerUpdate(meetingId: meetingId, speakers: roster));
    }

    // 3) 触发终稿链路（失败不影响停止流程本身）。
    //
    // **不要 await**：终稿链路包含「上传整段 WAV + 提交 filetrans」，
    // 弱网 / 大文件下可能耗时数十秒到数分钟。停录必须在这里立即返回，
    // 否则「结束并生成」按钮会一直转圈（历史 Bug）。
    // 失败统一落成 finalize_status=failed 并广播进度，由 UI 提示。
    bool finalizeTriggered = false;
    if (upload && audioKey != null) {
      final String? wavPath = await _resolveArchivePath(audioKey);
      if (wavPath != null) {
        unawaited(_triggerFinalizeInBackground(meetingId, wavPath));
        finalizeTriggered = true;
        logInfo('transcription', 'onStop·终稿链路已触发 meeting=$meetingId wav=$wavPath');
      } else {
        logWarn('transcription', 'onStop：归档路径解析失败，终稿未触发 meeting=$meetingId key=$audioKey');
      }
    } else {
      logWarn(
        'transcription',
        'onStop：未触发终稿（upload=$upload audioKey=${audioKey ?? 'null'}）',
      );
    }

    // A3 链路摘要：用户跑一次后最该发回来的一行（一眼看断在哪一环）。
    logInfo(
      'transcription',
      '链路摘要 meeting=$meetingId 录音=${durationMs}ms '
      '后端收帧=${runtime?.frameCount ?? 0} PCM=${runtime?.pcmBytes ?? 0}B '
      'WAV=${durationMs}ms/${wavBytes}B '
      '实时会话=${realtimeRunning ? '已连接' : '未连接'} 实时句子=$realtimeSentences '
      '终稿=${finalizeTriggered ? '提交中' : '未触发'} '
      '摘要片段=${(updated.minutesMd ?? '').length}字 总耗时=${watch.elapsedMilliseconds}ms',
    );
    return updated;
  }

  /// 后台触发终稿链路：失败落成 `finalize_status=failed` + 广播，不冒泡到停录流程。
  Future<void> _triggerFinalizeInBackground(String meetingId, String wavPath) async {
    try {
      await startFinalize(meetingId, wavPath: wavPath);
    } catch (error) {
      logWarn('transcription', '终稿链路失败 meeting=$meetingId：$error');
      await _markFinalizeFailed(meetingId, error.toString());
    }
  }

  /// 终稿链路失败时的兜底落盘 + 广播。
  Future<void> _markFinalizeFailed(String meetingId, String message) async {
    try {
      final Meeting? meeting = await persistence.loadMeeting(meetingId);
      if (meeting == null) return;
      await persistence.saveMeeting(
        meeting.copyWith(
          finalizeStatus: FinalizeStatus.failed,
          finalizeError: message,
        ),
      );
      _emit(FinalizeProgress(meetingId: meetingId, status: 'failed', error: message));
    } catch (error) {
      logWarn('transcription', '落盘终稿失败状态时出错 meeting=$meetingId：$error');
    }
  }

  /// 触发终稿转写链路（委托 [FinalizePoller]）。
  Future<void> startFinalize(String meetingId, {required String wavPath, bool diarization = true}) async {
    final FinalizePoller? poller = finalizePoller;
    if (poller == null) throw const AppError(ErrorCode.internal, 'finalizePoller 未装配');
    await poller.start(meetingId, wavPath: wavPath, diarization: diarization);
  }

  /// 终稿完成回调（由 [FinalizePoller] 调用）：**先落库再广播**。
  Future<void> handleFinalizeComplete(String meetingId, List<TranscriptSegment> segments) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting != null) {
      final List<TranscriptSegment> normalized =
          segments.map(normalizeSegment).toList(growable: false);
      // 空结果防误覆盖：终稿返回空但已有实时稿时保留实时稿，避免把已落库的
      // 逐字稿擦成空（「落库逐字稿为空」的一个直接成因）。
      final bool keepRealtime = normalized.isEmpty && meeting.segments.isNotEmpty;
      final List<TranscriptSegment> effective =
          keepRealtime ? meeting.segments : normalized;
      if (keepRealtime) {
        logWarn(
          'transcription',
          '终稿返回空结果，保留实时稿 meeting=$meetingId 现有=${meeting.segments.length} 段',
        );
      }
      final List<Speaker> roster = buildSpeakerRoster(effective, meetingId: meetingId);
      await persistence.saveMeeting(
        meeting.copyWith(
          segments: effective,
          speakers: roster,
          speakerCount: roster.length,
          finalizeStatus: FinalizeStatus.done,
          transcriptSource:
              keepRealtime ? meeting.transcriptSource : TranscriptSource.filetrans,
        ),
      );
      _emit(TranscriptReplace(meetingId: meetingId, segments: effective, speakers: roster));
      _emit(SpeakerUpdate(meetingId: meetingId, speakers: roster));
    }
    final SessionState? state = sessionStore.findByMeeting(meetingId);
    if (state != null && segments.isNotEmpty) {
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

  /// 后端实际收到的音频帧数（诊断用）。
  int frameCount = 0;

  /// 上次「音频汇总」日志的墙钟毫秒（每 5 秒一条）。
  int lastReportAtMs = 0;

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
