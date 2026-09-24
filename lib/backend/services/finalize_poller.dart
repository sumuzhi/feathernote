/// 终稿轮询器（filetrans 状态机），移植 `server/src/services/finalizePoller.js`。
///
/// 契约（**顺序不可变**）：
/// ```
/// 1) 收到本地 WAV → 立即落盘 finalize_status='pending'
/// 2) 异步：临时上传 → 提交 filetrans（diarization_enabled:true）→ 轮询 → 下载
/// 3) 解析成功：先【原子落盘】transcript 覆盖 + transcript_source='filetrans'
///             + finalize_status='done'（重算 speakers）
/// 4) 再【广播】transcript_replace
/// 失败路径：finalize_status='failed'，transcript 保持实时稿不覆盖
/// ```
///
/// 并发幂等：同一会议已有在途链路时复用同一次提交（同一 task_id），
/// 不重复「上传 + 提交」；守卫在终态落盘后释放，以便失败后重试。
library;

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/log/log.dart';
import '../../core/ws_protocol.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../algo/clustering.dart';
import '../engine/engine.dart';
import '../storage/meeting_repository.dart';

/// 可重试的错误码（网络 / 5xx / 限流）。业务失败不重试。
const Set<String> kRetryableEngineCodes = <String>{'E_SERVER', 'E_HTTP', 'E_RATE_LIMIT'};

/// 终稿任务态快照。
class FinalizeTask {
  /// 构造快照。
  const FinalizeTask({required this.taskId, required this.status, this.error});

  /// 百炼任务 ID。
  final String taskId;

  /// 状态（`pending` / `done` / `failed`）。
  final String status;

  /// 失败原因。
  final String? error;
}

/// 终稿轮询器。
class FinalizePoller {
  /// 构造轮询器。
  FinalizePoller({
    required this.engine,
    required this.persistence,
    required this.cfg,
    this.onComplete,
    this.onFailed,
    this.onProgress,
  });

  /// 引擎。
  final Engine engine;

  /// 持久化门面。
  final MeetingRepository persistence;

  /// 冻结配置。
  final AppConfig cfg;

  /// 成功回调（落盘后广播）。
  final Future<void> Function(String meetingId, List<TranscriptSegment> segments)? onComplete;

  /// 失败回调。
  final void Function(String meetingId, Object error)? onFailed;

  /// 进度回调（`pending` / `done` / `failed`）。
  final void Function(String meetingId, String status, String? taskId)? onProgress;

  final Map<String, FinalizeTask> _tasks = <String, FinalizeTask>{};
  final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 任务态快照。
  FinalizeTask? taskOf(String meetingId) => _tasks[meetingId];

  /// 启动终稿链路（**并发幂等**）。
  ///
  /// 返回时保证 `finalize_status='pending'` 已落盘；上传 / 提交失败则抛错。
  Future<String> start(String meetingId, {required String wavPath, bool diarization = true}) {
    final Future<String>? existing = _inflight[meetingId];
    if (existing != null) return existing;

    final Completer<String> deferred = Completer<String>();
    final Future<String> submitted = deferred.future;
    _inflight[meetingId] = submitted;

    void release() {
      if (_inflight[meetingId] == submitted) _inflight.remove(meetingId);
    }

    unawaited(
      Future<void>(() async {
        try {
          final Meeting? meeting = await persistence.loadMeeting(meetingId);
          if (meeting == null) throw StateError('会议不存在：$meetingId');
          // 1) 立即落盘 pending（刷新页面后仍能识别「有终稿在处理中」）。
          await persistence.saveMeeting(
            meeting.copyWith(finalizeStatus: FinalizeStatus.pending),
          );
          onProgress?.call(meetingId, 'pending', null);
          await _run(meetingId, wavPath, diarization, deferred);
        } catch (error) {
          if (!deferred.isCompleted) deferred.completeError(error);
        } finally {
          release();
        }
      }),
    );
    return submitted;
  }

  Future<void> _run(
    String meetingId,
    String wavPath,
    bool diarization,
    Completer<String> deferred,
  ) async {
    try {
      final String taskId = await _withRetry<String>(
        () => engine.submitFiletrans(wavPathOrUrl: wavPath, diarization: diarization),
        cfg.filetransMaxRetry,
        meetingId,
        '提交',
      );
      _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'pending');
      logInfo('finalize', 'filetrans 已提交 meeting=$meetingId task=$taskId');
      if (!deferred.isCompleted) deferred.complete(taskId);

      final FiletransResult result = await _withRetry<FiletransResult>(
        () => engine.waitFiletrans(taskId, interval: Duration(milliseconds: cfg.filetransPollIntervalMs)),
        cfg.filetransMaxRetry,
        meetingId,
        '轮询',
      );
      if (!result.isSucceeded) {
        throw StateError(result.error ?? 'filetrans 未成功');
      }
      // 2) 先落盘（覆盖 transcript），再广播。
      await _persistDone(meetingId, result.segments);
      _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'done');
      logInfo('finalize', '终稿已落盘 meeting=$meetingId 句数=${result.segments.length}');
      onProgress?.call(meetingId, 'done', taskId);
      if (onComplete != null) await onComplete!(meetingId, result.segments);
    } catch (error) {
      final String message = error.toString();
      logWarn('finalize', '终稿失败 meeting=$meetingId：$message');
      _tasks[meetingId] = FinalizeTask(
        taskId: _tasks[meetingId]?.taskId ?? '',
        status: 'failed',
        error: message,
      );
      if (!deferred.isCompleted) deferred.completeError(error);
      await _persistFailed(meetingId, message);
      onProgress?.call(meetingId, 'failed', null);
      onFailed?.call(meetingId, error);
    }
  }

  /// 带退避重试的执行包装（仅对网络 / 5xx / 限流重试）。
  Future<T> _withRetry<T>(
    Future<T> Function() fn,
    int retries,
    String meetingId,
    String stage,
  ) async {
    final int max = retries < 0 ? 0 : retries;
    Object? lastError;
    for (int attempt = 0; attempt <= max; attempt++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        final bool retryable = error is AppError
            ? kRetryableEngineCodes.contains(error.engineCode)
            : true;
        if (attempt >= max || !retryable) break;
        final int backoff = 1000 * (1 << attempt);
        logWarn(
          'finalize',
          '$stage 失败将重试(${attempt + 1}/$max) meeting=$meetingId',
          <String, Object?>{'error': error.toString()},
        );
        await Future<void>.delayed(Duration(milliseconds: backoff));
      }
    }
    throw lastError ?? StateError('$stage 失败');
  }

  /// 成功落盘（覆盖 transcript + done，重算说话人）。
  Future<void> _persistDone(String meetingId, List<TranscriptSegment> segments) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    final List<Speaker> roster = buildSpeakerRoster(segments, meetingId: meetingId);
    final int derived = segments.isEmpty
        ? 0
        : segments.map((TranscriptSegment s) => s.endTime).reduce((int a, int b) => a > b ? a : b);
    await persistence.saveMeeting(
      meeting.copyWith(
        segments: segments,
        finalizeStatus: FinalizeStatus.done,
        transcriptSource: TranscriptSource.filetrans,
        speakers: roster,
        speakerCount: roster.length,
        durationMs: meeting.durationMs > derived ? meeting.durationMs : derived,
      ),
    );
  }

  /// 失败落盘（保留实时稿，仅置 failed）。
  Future<void> _persistFailed(String meetingId, String message) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    await persistence.saveMeeting(
      meeting.copyWith(finalizeStatus: FinalizeStatus.failed, finalizeError: message),
    );
  }

  /// 当前是否有在途链路。
  bool isInflight(String meetingId) => _inflight.containsKey(meetingId);

  /// 终态常量（避免调用方硬编码字符串）。
  static String get statusDone => TaskStatus.succeeded;

  /// 失败态常量。
  static String get statusFailed => TaskStatus.failed;
}
