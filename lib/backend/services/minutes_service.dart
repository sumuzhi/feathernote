/// 纪要编排服务：逐字稿 → Prompt → LLM 流式 → 按结局落盘。
///
/// 移植 `server/src/services/minutesService.js`（含 Wave L 结局语义）：
/// - (a) 正常跑完 → `minutes_md` + `status='minutes_ready'` + `minutes_partial=false`，清空 `minutes_error`；
/// - (b) 引擎抛错（超时 / 截断 / 网络）→ **不标记为完成**；若库中已有完整纪要则**绝不覆盖**，
///   否则落残篇 + `status='stopped'` + `minutes_partial=true` + `minutes_error`；
/// - (c) 订阅方提前取消 → 降级为残篇语义（同上，已有完整纪要不覆盖）。
library;

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../engine/engine.dart';
import '../storage/meeting_repository.dart';
import 'prompts.dart';

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
  /// 短路：仅当库中已有**完整**纪要（非残篇）且 `force=false` 时直接回库；
  /// 残篇不视为可用缓存 —— 「未完成的内容不该伪装成已完成」。
  Stream<String> generateStream(String meetingId, {bool force = false}) async* {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) {
      throw AppError(ErrorCode.notFound, '会议不存在：$meetingId');
    }
    if (!force && meeting.minutesMd != null && !meeting.minutesPartial) {
      logInfo(
        'minutes',
        '纪要命中缓存，直接回库 meeting=$meetingId 长度=${meeting.minutesMd!.length}',
      );
      yield meeting.minutesMd!;
      return;
    }

    // **空逐字稿守卫**：绝不给 LLM 喂空输入。历史缺陷：停录收尾尚未落库时，
    // 详情页"抢跑"生成 → 读到 0 段逐字稿 → LLM 产出 979 字**无源摘要**（垃圾）。
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
    final bool hadComplete = meeting.minutesMd != null && !meeting.minutesPartial;
    final StringBuffer markdown = StringBuffer();
    bool completed = false;
    Object? failure;
    int promptChars = 0;
    for (final LlmMessage message in messages) {
      promptChars += message.content.length;
    }
    final Stopwatch watch = Stopwatch()..start();
    int firstTokenMs = -1;
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

    try {
      await for (final String delta in engine.chatStream(
        messages,
        options: LlmOptions(
          temperature: cfg.llmTemperature,
          maxTokens: cfg.llmMaxTokens,
          enableThinking: cfg.llmEnableThinking,
          model: cfg.llmModel,
        ),
      )) {
        if (firstTokenMs < 0) {
          firstTokenMs = watch.elapsedMilliseconds;
          logInfo('minutes', '纪要首字节到达 meeting=$meetingId 延迟=${firstTokenMs}ms');
        }
        markdown.write(delta);
        yield delta;
      }
      completed = true;
      logInfo(
        'minutes',
        '纪要生成结束 meeting=$meetingId 字符=${markdown.length} '
        '首字延迟=${firstTokenMs < 0 ? '—' : '${firstTokenMs}ms'} 总耗时=${watch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      failure = error;
      logWarn(
        'minutes',
        '纪要生成失败 meeting=$meetingId 已产出=${markdown.length}字 '
        '首字延迟=${firstTokenMs < 0 ? '—' : '${firstTokenMs}ms'} '
        '耗时=${watch.elapsedMilliseconds}ms 原因=$error',
      );
    } finally {
      // 落盘恒在 finally：订阅方提前取消时生成器在 yield 处结束，
      // 只有 finally 能保住已生成内容。
      await _persistOutcome(
        meeting,
        meetingId,
        markdown: markdown.toString(),
        completed: completed,
        failure: failure,
        hadComplete: hadComplete,
      );
    }
    if (failure != null) throw failure;
  }

  /// 非流式生成纪要。
  Future<String> generate(String meetingId, {bool force = false}) async {
    final StringBuffer buffer = StringBuffer();
    await for (final String delta in generateStream(meetingId, force: force)) {
      buffer.write(delta);
    }
    return buffer.toString();
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
