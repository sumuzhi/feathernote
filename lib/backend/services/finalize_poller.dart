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
import '../../core/platform/recording_foreground_service.dart';
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

  /// filetrans 提交成功回调（导入链路用于落库 `import_task_id`，§4.4 ②恢复依据）。
  ///
  /// 可变字段：[ImportService] 构造时注入（di 不感知，零装配改动）。
  void Function(String meetingId, String taskId)? onTaskSubmitted;

  /// 终稿成功落盘后**自动生成纪要**回调（可变字段，di 装配后注入
  /// `minutesService.startBackground`）。
  ///
  /// 2026-10-10 起「结束录音 → 立即录下一段」：纪要生成不能再依赖详情页存活
  /// （用户可能早已退出详情页）。只在**录音路径**（[start]，source='wav'）触发；
  /// 导入链路有自己的 step4 编排，不在此触发。
  void Function(String meetingId)? onAutoMinutes;

  /// 需要自动生成纪要的会议集合（录音路径标记，终稿落盘后消费）。
  final Set<String> _autoMinutes = <String>{};

  final Map<String, FinalizeTask> _tasks = <String, FinalizeTask>{};
  final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 已放弃（导入取消）的会议集合：[_run] 在各检查点看到后静默停止推进。
  final Set<String> _abandoned = <String>{};

  /// 任务态快照。
  FinalizeTask? taskOf(String meetingId) => _tasks[meetingId];

  /// 启动终稿链路（**并发幂等**）。
  ///
  /// 契约：**返回时只保证 `finalize_status='pending'` 已落盘**，
  /// 上传整段 WAV / 提交 filetrans / 轮询全部在后台继续，不阻塞调用方。
  ///
  /// 为什么必须这样：停录路径如果把「上传 + 提交」await 在关键路径上，
  /// 弱网或大文件时 UI 的「结束并生成」会一直转圈（`uploadTimeoutMs` 默认 120s）。
  /// 因此这里在 pending 落盘后立即 complete；只有「会议不存在 / pending 落盘失败」
  /// 这类**同步可判定**的错误才通过返回的 Future 抛出。
  Future<String> start(String meetingId, {required String wavPath, bool diarization = true}) =>
      _startInternal(meetingId, wavPath, diarization, source: 'wav');

  /// 启动终稿链路（`oss://` 直通版，导入链路 step3 专用，设计文档 §3.2）。
  ///
  /// 与 [start] 的唯一区别：调用方已完成流式上传并持有 `oss://` URL，
  /// 引擎侧 `submitFiletrans` 对 `oss://` 直通不再重复上传；
  /// 提交 → 轮询 → 落盘 → 广播语义与 [start] 完全一致（受理契约不变）。
  Future<String> startWithOssUrl(String meetingId, {required String ossUrl, bool diarization = true}) =>
      _startInternal(meetingId, ossUrl, diarization, source: 'oss');

  /// [start] / [startWithOssUrl] 的公共受理段。
  Future<String> _startInternal(
    String meetingId,
    String fileOrUrl,
    bool diarization, {
    required String source,
  }) {
    final Future<String>? existing = _inflight[meetingId];
    if (existing != null) return existing;
    // 重试场景：清除上一次的放弃标志。
    _abandoned.remove(meetingId);
    // 录音路径（source='wav'）标记「终稿成功后自动生成纪要」；导入链路
    // （oss / resume）有自己的 step4 编排，不标记。
    if (source == 'wav') _autoMinutes.add(meetingId);

    final Completer<String> accepted = Completer<String>();
    final Future<String> submitted = accepted.future;
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
          logInfo(
            'finalize',
            '终稿已受理 meeting=$meetingId（pending 已落盘，后台继续）',
            <String, Object?>{'input': fileOrUrl, 'source': source},
          );
          onProgress?.call(meetingId, 'pending', null);
          // 2) 契约点：pending 已落盘 → 立刻交还控制权（taskId 由进度回调补全）。
          if (!accepted.isCompleted) accepted.complete('');
          // 3) 上传（若为本地路径）/ 提交 / 轮询后台化。
          await _run(meetingId, fileOrUrl, diarization);
        } catch (error) {
          if (!accepted.isCompleted) {
            accepted.completeError(error);
          }
          logWarn('finalize', '终稿链路启动失败 meeting=$meetingId：$error');
          await _persistFailed(meetingId, error.toString());
          onProgress?.call(meetingId, 'failed', null);
          onFailed?.call(meetingId, error);
        } finally {
          release();
        }
      }),
    );
    return submitted;
  }

  /// 放弃在途终稿（导入取消专用，设计文档 §4.3）。
  ///
  /// 语义：**本地停止推进 + 落 `finalize_status='failed'`**。无百炼取消 API，
  /// 已提交的 filetrans 异步任务不撤销，服务端任务自然跑完即作废（临时 OSS 24h 过期）。
  /// 若 [_run] 正在等待轮询，会在下一个检查点看到放弃标志后静默返回。
  /// 只发 [onProgress] 不发 [onFailed]——失败处理由导入编排层（ImportService）统一负责。
  Future<void> abandon(String meetingId) async {
    _abandoned.add(meetingId);
    unawaited(_inflight.remove(meetingId));
    _tasks.remove(meetingId);
    await _persistFailed(meetingId, '用户取消');
    onProgress?.call(meetingId, 'failed', null);
    logInfo('finalize', '终稿已放弃 meeting=$meetingId（本地停止推进，服务端任务自然作废）');
  }

  /// 后台执行段：上传 → 提交 → 轮询 → 落盘 / 广播。不参与 [start] 的返回契约。
  Future<void> _run(String meetingId, String wavPath, bool diarization) async {
    final String keepAliveHolder = 'finalize/$meetingId';
    // 保活：终稿链路（上传 + filetrans 轮询）可达数分钟，切后台无前台服务
    // 时进程可被系统随时回收 → 终稿中断只能靠重启恢复。
    // 不 await：`_run` 必须在首个微任务内走到 submit（start 契约测试固化了
    // 「start 返回即已开跑」的可见性）；acquire 对持有者集合的登记是同步的，
    // 引用计数依然配对安全（finally release）。
    unawaited(
      RecordingForegroundService.instance.acquire(
        keepAliveHolder,
        notificationText: '正在转写录音（终稿处理）…',
      ),
    );
    try {
      if (_abandoned.contains(meetingId)) return;
      final String taskId = await _withRetry<String>(
        () => engine.submitFiletrans(wavPathOrUrl: wavPath, diarization: diarization),
        cfg.filetransMaxRetry,
        meetingId,
        '提交',
      );
      if (_abandoned.contains(meetingId)) return;
      _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'pending');
      logInfo('finalize', 'filetrans 已提交 meeting=$meetingId task=$taskId');
      onProgress?.call(meetingId, 'pending', taskId);
      onTaskSubmitted?.call(meetingId, taskId);

      await _pollAndPersist(meetingId, taskId);
    } catch (error) {
      // 放弃后的迟到异常（如网络抖动）不覆盖「用户取消」失败态。
      if (_abandoned.contains(meetingId)) {
        logInfo('finalize', '终稿已放弃，忽略迟到异常 meeting=$meetingId：$error');
        return;
      }
      final String? knownTaskId = _tasks[meetingId]?.taskId;
      await _handleRunFailure(meetingId, knownTaskId ?? '', error);
    } finally {
      await RecordingForegroundService.instance.release(keepAliveHolder);
    }
  }

  /// 恢复轮询（App 被杀后导入恢复专用，设计 §4.4 ②）。
  ///
  /// 与 [startWithOssUrl] 的区别：任务**已提交**（importTaskId 非空），
  /// 跳过上传与提交，直接 `waitFiletrans(taskId)` → 落盘 → 广播（taskId 幂等）。
  Future<String> resumeWithTaskId(String meetingId, {required String taskId}) {
    final Future<String>? existing = _inflight[meetingId];
    if (existing != null) return existing;
    _abandoned.remove(meetingId);

    final Completer<String> accepted = Completer<String>();
    final Future<String> submitted = accepted.future;
    _inflight[meetingId] = submitted;

    unawaited(
      Future<void>(() async {
        final String keepAliveHolder = 'finalize/$meetingId';
        try {
          _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'pending');
          onProgress?.call(meetingId, 'pending', taskId);
          if (!accepted.isCompleted) accepted.complete('');
          await RecordingForegroundService.instance.acquire(
            keepAliveHolder,
            notificationText: '正在转写录音（终稿处理）…',
          );
          await _pollAndPersist(meetingId, taskId);
        } catch (error) {
          if (!accepted.isCompleted) accepted.complete('');
          if (_abandoned.contains(meetingId)) {
            logInfo('finalize', '终稿已放弃，忽略迟到异常 meeting=$meetingId：$error');
            return;
          }
          await _handleRunFailure(meetingId, taskId, error);
        } finally {
          await RecordingForegroundService.instance.release(keepAliveHolder);
          if (_inflight[meetingId] == submitted) {
            unawaited(_inflight.remove(meetingId));
          }
        }
      }),
    );
    return submitted;
  }

  /// 轮询 → 落盘 → 广播（[start] 链路与 [resumeWithTaskId] 共用的后半段）。
  Future<void> _pollAndPersist(String meetingId, String taskId) async {
    final FiletransResult result = await _withRetry<FiletransResult>(
      () => engine.waitFiletrans(taskId, interval: Duration(milliseconds: cfg.filetransPollIntervalMs)),
      cfg.filetransMaxRetry,
      meetingId,
      '轮询',
    );
    // 放弃检查点：等待轮询期间被取消 → 静默返回（abandon 已落 failed）。
    if (_abandoned.contains(meetingId)) {
      logInfo('finalize', '轮询期间被放弃，跳过落盘 meeting=$meetingId');
      return;
    }
    if (!result.isSucceeded) {
      throw StateError(result.error ?? 'filetrans 未成功');
    }
    // 2) 先落盘（覆盖 transcript），再广播。
    await _persistDone(meetingId, result.segments);
    _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'done');
    logInfo('finalize', '终稿已落盘 meeting=$meetingId 句数=${result.segments.length}');
    onProgress?.call(meetingId, 'done', taskId);
    if (onComplete != null) await onComplete!(meetingId, result.segments);
    // 3) 录音路径 → 自动触发后台纪要生成（与页面解耦；详情页随后订阅会
    //    附着同一 per-meeting 单飞流）。空逐字稿时 MinutesService 自有守卫拒绝。
    if (_autoMinutes.remove(meetingId) == true) {
      logInfo('finalize', '终稿完成，自动触发后台纪要生成 meeting=$meetingId');
      onAutoMinutes?.call(meetingId);
    }
  }

  /// 统一失败处理：置内存态 + 落 failed + 回调（[start] / [resumeWithTaskId] 共用）。
  Future<void> _handleRunFailure(String meetingId, String taskId, Object error) async {
    final String message = error.toString();
    logWarn('finalize', '终稿失败 meeting=$meetingId：$message');
    _autoMinutes.remove(meetingId); // 失败不自动生成（重试成功后会重新标记）
    _tasks[meetingId] = FinalizeTask(taskId: taskId, status: 'failed', error: message);
    await _persistFailed(meetingId, message);
    onProgress?.call(meetingId, 'failed', null);
    onFailed?.call(meetingId, error);
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
    // 空结果防误覆盖：终稿返回空但已有实时稿时保留实时稿，
    // 否则会把已落库的逐字稿擦成空（「落库逐字稿为空」的直接成因之一）。
    final bool keepRealtime = segments.isEmpty && meeting.segments.isNotEmpty;
    final List<TranscriptSegment> effective = keepRealtime ? meeting.segments : segments;
    if (keepRealtime) {
      logWarn(
        'finalize',
        '终稿返回空结果，保留实时稿 meeting=$meetingId 现有=${meeting.segments.length} 段',
      );
    }
    final List<Speaker> roster = buildSpeakerRoster(effective, meetingId: meetingId);
    final int derived = effective.isEmpty
        ? 0
        : effective.map((TranscriptSegment s) => s.endTime).reduce((int a, int b) => a > b ? a : b);
    await persistence.saveMeeting(
      meeting.copyWith(
        segments: effective,
        finalizeStatus: FinalizeStatus.done,
        transcriptSource:
            keepRealtime ? meeting.transcriptSource : TranscriptSource.filetrans,
        speakers: roster,
        speakerCount: roster.length,
        durationMs: meeting.durationMs > derived ? meeting.durationMs : derived,
      ),
    );
    logInfo(
      'finalize',
      '终稿落库完成（覆盖逐字稿）',
      <String, Object?>{
        'meeting': meetingId,
        'segments': effective.length,
        '保留实时稿': keepRealtime,
        'speakers': roster.length,
        'durationMs': meeting.durationMs > derived ? meeting.durationMs : derived,
      },
    );
  }

  /// 失败落盘（保留实时稿，仅置 failed）。
  Future<void> _persistFailed(String meetingId, String message) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    await persistence.saveMeeting(
      meeting.copyWith(finalizeStatus: FinalizeStatus.failed, finalizeError: message),
    );
    logWarn(
      'finalize',
      '终稿落库失败态 meeting=$meetingId（逐字稿保持实时稿不覆盖）原因=$message',
    );
  }

  /// 当前是否有在途链路。
  bool isInflight(String meetingId) => _inflight.containsKey(meetingId);

  /// 终态常量（避免调用方硬编码字符串）。
  static String get statusDone => TaskStatus.succeeded;

  /// 失败态常量。
  static String get statusFailed => TaskStatus.failed;
}
