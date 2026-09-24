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
      yield meeting.minutesMd!;
      return;
    }

    final List<LlmMessage> messages = await buildMinutesMessages(meeting);
    final bool hadComplete = meeting.minutesMd != null && !meeting.minutesPartial;
    final StringBuffer markdown = StringBuffer();
    bool completed = false;
    Object? failure;

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
        markdown.write(delta);
        yield delta;
      }
      completed = true;
    } catch (error) {
      failure = error;
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

  /// 静默落盘（失败仅告警，不抛出，避免掩盖生成错误）。
  Future<bool> _saveQuietly(Meeting meeting, String meetingId, String note) async {
    try {
      await persistence.saveMeeting(meeting);
      logInfo(
        'minutes',
        '$note meeting=$meetingId 长度=${(meeting.minutesMd ?? '').length}',
      );
      return true;
    } catch (error) {
      logWarn('minutes', '纪要落盘失败 meeting=$meetingId：$error');
      return false;
    }
  }

  /// 按结局落盘（三种退出，见库级文档）。
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
        await _saveQuietly(
          meeting.copyWith(minutesError: readableError(failure)),
          meetingId,
          '生成失败，保留原完整纪要',
        );
        return;
      }
      await _saveQuietly(
        meeting.copyWith(
          minutesMd: hasContent ? markdown : meeting.minutesMd,
          status: MeetingStatus.stopped,
          minutesPartial: true,
          minutesError: readableError(failure),
        ),
        meetingId,
        '残篇已落盘（生成中断）',
      );
      return;
    }

    if (completed) {
      if (hasContent) {
        await _saveQuietly(
          meeting.copyWith(
            minutesMd: markdown,
            status: MeetingStatus.minutesReady,
            minutesPartial: false,
            minutesError: null,
          ),
          meetingId,
          '纪要已落盘',
        );
      }
      return;
    }

    // 订阅方主动取消：保留进度但降级为残篇（不标完成）。
    if (hasContent && !hadComplete) {
      await _saveQuietly(
        meeting.copyWith(
          minutesMd: markdown,
          status: MeetingStatus.stopped,
          minutesPartial: true,
          minutesError: meeting.minutesError ?? '生成中断（未完成）',
        ),
        meetingId,
        '残篇已落盘（订阅方取消）',
      );
    }
  }
}
