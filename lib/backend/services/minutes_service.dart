/// 纪要编排服务：逐字稿 → Prompt → LLM 流式 → 按结局落盘。
///
/// 移植 `server/src/services/minutesService.js`（含 Wave L 结局语义）：
/// - (a) 正常跑完 → `minutes_md` + `status='minutes_ready'` + `minutes_partial=false`，清空 `minutes_error`；
/// - (b) 引擎抛错（超时 / 截断 / 网络）→ **不标记为完成**；若库中已有完整纪要则**绝不覆盖**，
///   否则落残篇 + `status='stopped'` + `minutes_partial=true` + `minutes_error`；
/// - (c) 订阅方提前取消 → **不再中止生成**（2026-10-09 修复）：生成生命周期上收到服务层，
///   页面退出只是「不再观看」，生成继续跑完并落盘完整纪要；重进时附着现有流续看。
///   旧语义（取消即落残篇）正是「历史 desc 与最终纪要不一致」的根源：残篇被新一轮
///   生成覆盖，而摘录来自旧残篇。
library;

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/log/log.dart';
import '../../core/platform/recording_foreground_service.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../engine/engine.dart';
import '../storage/meeting_repository.dart';
import 'prompts.dart';

/// 进行中的生成任务（**per-meeting 单飞**的运行态）。
class _ActiveGeneration {
  /// 已产出的完整 Markdown（重放进附着流用）。
  final StringBuffer buffer = StringBuffer();

  /// 增量广播通道：`_runGeneration` 生产，附着流消费。
  final StreamController<String> controller = StreamController<String>.broadcast();

  /// 被 `force` 重启作废：停止消费引擎流、**不落盘**。
  bool superseded = false;
}

/// 纪要编排服务。
class MinutesService {
  /// 构造服务。
  MinutesService({required this.engine, required this.persistence, required this.cfg});

  /// 引擎。
  final Engine engine;

  /// 持久化门面。
  final MeetingRepository persistence;

  /// 冻结配置。
  final AppConfig cfg;

  /// 进行中的生成任务（meetingId → 任务）。
  ///
  /// 修复「未生成完退出重进会从头再生成」：同一会议**同时只允许一轮生成**——
  /// 详情页与导入链路（`import_service`）并发请求时共享同一流，绝不重复调
  /// LLM、不互相覆盖落盘。
  final Map<String, _ActiveGeneration> _active = <String, _ActiveGeneration>{};

  /// 把引擎错误翻译为可读的中断原因（供前端提示）。
  static String readableError(Object error) {
    final String? code = error is AppError ? error.engineCode : null;
    final String raw = error.toString();
    if (code == 'E_TRUNCATED' || raw.contains('截断')) return '生成中断：输出被 max_tokens 截断';
    if (code == 'E_TIMEOUT' ||
        code == 'E_HTTP' && raw.contains('超时') ||
        raw.contains('TimeoutException') ||
        raw.toLowerCase().contains('timeout')) {
      return '生成中断：请求超时';
    }
    return '生成中断：$raw';
  }

  /// 流式生成纪要（打字机用）。
  ///
  /// - 库中已有**完整**纪要且 `force=false` → 直接回库（缓存短路）；
  /// - 同会议已有生成在跑 → **附着**现有流（先重放已产出内容，再续收增量），
  ///   不重复生成——重进详情页即此路径；
  /// - `force=true` 且已有生成在跑 → 作废旧流（**不落盘**），重启新一轮。
  Stream<String> generateStream(String meetingId, {bool force = false}) {
    final _ActiveGeneration? running = _active[meetingId];
    if (running != null && !running.superseded) {
      if (!force) {
        logInfo(
          'minutes',
          '纪要生成进行中，附着现有流 meeting=$meetingId 已产出=${running.buffer.length}字',
        );
        return _attach(running);
      }
      logInfo(
        'minutes',
        '纪要强制重生成，作废旧流（不落盘）meeting=$meetingId 已产出=${running.buffer.length}字',
      );
      running.superseded = true;
      if (!running.controller.isClosed) {
        unawaited(running.controller.close());
      }
      _active.remove(meetingId);
    }
    final _ActiveGeneration task = _ActiveGeneration();
    _active[meetingId] = task;
    return _startAndAttach(task, meetingId, force: force);
  }

  /// 首个订阅者：**监听时才启动**主循环，随后直通消费。
  ///
  /// 启动放在 listen 之后（而非 generateStream 调用之时）：主循环的同步段内
  /// 先启动、后订阅，守卫类急抛错误（会议不存在 / 空逐字稿）就不会早于订阅
  /// 被 broadcast 控制器丢弃。`yield*` 直通同时保证订阅者 cancel 立即生效
  /// （`await for` 转发会让 cancel 挂到内层流结束——实测复现）。
  Stream<String> _startAndAttach(
    _ActiveGeneration task,
    String meetingId, {
    required bool force,
  }) async* {
    unawaited(_runGeneration(task, meetingId, force: force));
    yield* task.controller.stream;
  }

  /// 附着一个生成任务：先重放已产出内容，再续收实时增量。
  ///
  /// 生成主循环由 [_runGeneration] 独立驱动，本流**只读**——订阅者取消
  /// 不影响生成与落盘。
  Stream<String> _attach(_ActiveGeneration task) async* {
    if (task.buffer.isNotEmpty) {
      yield task.buffer.toString();
    }
    yield* task.controller.stream;
  }

  /// 生成主循环：**独立于订阅者生命周期**，结局恒落盘（被作废除外）。
  Future<void> _runGeneration(
    _ActiveGeneration task,
    String meetingId, {
    required bool force,
  }) async {
    bool completed = false;
    Object? failure;
    Meeting? meeting;
    bool hadComplete = false;
    // 前置守卫（会议不存在 / 空逐字稿 / Prompt 构建失败）不触发落盘——
    // 与旧实现一致：只有引擎流真正启动后，结局才参与落盘。
    bool engineStarted = false;
    // 保活持有标记：acquire 成功后 finally 里必须配对 release（非 Android 是 no-op）。
    bool keepAliveHeld = false;
    final Stopwatch watch = Stopwatch()..start();
    int firstTokenMs = -1;
    try {
      meeting = await persistence.loadMeeting(meetingId);
      if (meeting == null) {
        throw AppError(ErrorCode.notFound, '会议不存在：$meetingId');
      }
      if (!force && meeting.minutesMd != null && !meeting.minutesPartial) {
        logInfo(
          'minutes',
          '纪要命中缓存，直接回库 meeting=$meetingId 长度=${meeting.minutesMd!.length}',
        );
        task.buffer.write(meeting.minutesMd!);
        task.controller.add(meeting.minutesMd!);
        return;
      }

      // **空逐字稿守卫**：绝不给 LLM 喂空输入。历史缺陷：停录收尾尚未落库时，
      // 详情页"抢跑"生成 → 读到 0 段逐字稿 → LLM 产出**无源摘要**（垃圾）。
      // 这里直接拒绝并返回可读错误，由 UI 提示 + 重试。
      if (meeting.segments.isEmpty) {
        logWarn(
          'minutes',
          '逐字稿为空，拒绝生成纪要 meeting=$meetingId（避免无源摘要；'
          'finalizeStatus=${meeting.finalizeStatus.value}）',
        );
        throw const AppError(ErrorCode.badRequest, '逐字稿为空，暂无法生成纪要');
      }

      final List<LlmMessage> messages = await buildMinutesMessages(meeting);
      hadComplete = meeting.minutesMd != null && !meeting.minutesPartial;
      int promptChars = 0;
      for (final LlmMessage message in messages) {
        promptChars += message.content.length;
      }
      logInfo(
        'minutes',
        '纪要生成开始 meeting=$meetingId',
        <String, Object?>{
          'model': cfg.llmModel,
          'strategy': cfg.summaryStrategy,
          'promptChars': promptChars,
          'messages': messages.length,
          'force': force,
          'transcriptSegments': meeting.segments.length,
          'enableThinking': cfg.llmEnableThinking,
          'maxTokens': cfg.llmMaxTokens,
        },
      );

      engineStarted = true;
      // 保活：生成为 LLM 流式网络任务（分钟级），无前台服务时切后台/锁屏
      // 进程可被系统随时回收 → 生成中断。持有至落盘完成后释放。
      await RecordingForegroundService.instance.acquire(
        'minutes/$meetingId',
        notificationText: '正在生成纪要，请勿强制关闭',
      );
      keepAliveHeld = true;
      await for (final String delta in engine.chatStream(
        messages,
        options: LlmOptions(
          temperature: cfg.llmTemperature,
          maxTokens: cfg.llmMaxTokens,
          enableThinking: cfg.llmEnableThinking,
          model: cfg.llmModel,
        ),
      )) {
        if (task.superseded) break; // 被 force 重启作废：停止消费，不落盘
        if (firstTokenMs < 0) {
          firstTokenMs = watch.elapsedMilliseconds;
          logInfo('minutes', '纪要首字节到达 meeting=$meetingId 延迟=${firstTokenMs}ms');
        }
        task.buffer.write(delta);
        task.controller.add(delta);
      }
      if (task.superseded) {
        logInfo(
          'minutes',
          '纪要生成已作废，跳过落盘 meeting=$meetingId 已产出=${task.buffer.length}字',
        );
        return;
      }
      completed = true;
      logInfo(
        'minutes',
        '纪要生成结束 meeting=$meetingId 字符=${task.buffer.length} '
        '首字延迟=${firstTokenMs < 0 ? '—' : '${firstTokenMs}ms'} 总耗时=${watch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      failure = error;
      if (!task.superseded) {
        logWarn(
          'minutes',
          '纪要生成失败 meeting=$meetingId 已产出=${task.buffer.length}字 '
          '首字延迟=${firstTokenMs < 0 ? '—' : '${firstTokenMs}ms'} '
          '耗时=${watch.elapsedMilliseconds}ms 原因=$error',
        );
      }
    } finally {
      if (_active[meetingId] == task) {
        _active.remove(meetingId);
      }
      if (!task.superseded) {
        // 落盘恒在收尾：**与订阅者解耦后，取消不再触发残篇**，
        // 只有引擎流启动后的真实失败才落残篇（结局语义见库级文档）。
        if (engineStarted && meeting != null) {
          await _persistOutcome(
            meeting,
            meetingId,
            markdown: task.buffer.toString(),
            completed: completed,
            failure: failure,
            hadComplete: hadComplete,
          );
        }
        // 错误在落盘**之后**才抛给订阅者：保证订阅者刷新时读到的已是落盘后的库。
        if (failure != null) {
          task.controller.addError(failure);
        }
      }
      if (keepAliveHeld) {
        await RecordingForegroundService.instance.release('minutes/$meetingId');
        keepAliveHeld = false;
      }
      if (!task.controller.isClosed) {
        unawaited(task.controller.close());
      }
    }
  }

  /// 非流式生成纪要。
  Future<String> generate(String meetingId, {bool force = false}) async {
    final StringBuffer buffer = StringBuffer();
    await for (final String delta in generateStream(meetingId, force: force)) {
      buffer.write(delta);
    }
    return buffer.toString();
  }

  /// **后台静默生成**（终稿完成自动触发，2026-10-10）。
  ///
  /// 用户可在终稿跑完后立刻去录下一段、甚至早已退出详情页——纪要生成必须
  /// 不依赖任何页面存活，跑完即落盘（结局语义见 [generateStream]）。失败仅
  /// 告警不上抛（后台无人消费）。与详情页的手动生成共享 per-meeting 单飞：
  /// 页面随后订阅只是**附着**同一流，绝不重复调 LLM。
  void startBackground(String meetingId) {
    unawaited(() async {
      try {
        await generate(meetingId);
        logInfo('minutes', '后台纪要生成完成 meeting=$meetingId');
      } catch (error) {
        logWarn('minutes', '后台纪要生成失败 meeting=$meetingId：$error');
      }
    }());
  }

  /// 静默**窄更新**纪要列（失败仅告警，不抛出，避免掩盖生成错误）。
  ///
  /// 只写 `minutes_md` / `status` / `minutes_partial` / `minutes_error`，
  /// **绝不回写** `segments` / `speakers` / `duration_ms` / `audio_key` /
  /// `finalize_status` —— 从根上杜绝「读-改-写覆盖」把逐字稿擦成空。
  Future<bool> _updateMinutesQuietly(
    String meetingId, {
    required String note,
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {
    try {
      await persistence.updateMinutes(
        meetingId,
        minutesMd: minutesMd,
        status: status,
        minutesPartial: minutesPartial,
        minutesError: minutesError,
        clearMinutesError: clearMinutesError,
      );
      logInfo('minutes', '$note meeting=$meetingId');
      return true;
    } catch (error) {
      logWarn('minutes', '纪要窄更新失败 meeting=$meetingId：$error');
      return false;
    }
  }

  /// 按结局落盘（三种退出，见库级文档）。
  ///
  /// **只走窄更新**（[MeetingRepository.updateMinutes]），绝不整体回写 Meeting，
  /// 以免用生成开始时的过期副本覆盖期间已落库的逐字稿。
  Future<void> _persistOutcome(
    Meeting meeting,
    String meetingId, {
    required String markdown,
    required bool completed,
    required Object? failure,
    required bool hadComplete,
  }) async {
    final bool hasContent = markdown.trim().isNotEmpty;

    if (failure != null) {
      if (hadComplete) {
        // 已有完整纪要 → 绝不覆盖，仅记录错误。
        await _updateMinutesQuietly(
          meetingId,
          note: '生成失败，保留原完整纪要',
          minutesError: readableError(failure),
        );
        return;
      }
      await _updateMinutesQuietly(
        meetingId,
        note: '残篇已落盘（生成中断）',
        minutesMd: hasContent ? markdown : null,
        status: MeetingStatus.stopped,
        minutesPartial: true,
        minutesError: readableError(failure),
      );
      return;
    }

    if (completed) {
      if (hasContent) {
        await _updateMinutesQuietly(
          meetingId,
          note: '纪要已落盘',
          minutesMd: markdown,
          status: MeetingStatus.minutesReady,
          minutesPartial: false,
          clearMinutesError: true,
        );
      }
      return;
    }

    // 订阅方主动取消：保留进度但降级为残篇（不标完成）。
    // （2026-10-09 起生成与订阅解耦，此分支仅在引擎流自然结束却未标记完成时触达。）
    if (hasContent && !hadComplete) {
      await _updateMinutesQuietly(
        meetingId,
        note: '残篇已落盘（订阅方取消）',
        minutesMd: markdown,
        status: MeetingStatus.stopped,
        minutesPartial: true,
        minutesError: meeting.minutesError ?? '生成中断（未完成）',
      );
    }
  }
}
