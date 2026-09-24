/// 纪要提示词装配（移植 `core/summaryStrategies.js` 的插值逻辑 + 知识萃取模板）。
///
/// 模板本体逐字来自 `assets/prompts/minutes.md`（复制自原项目
/// `server/src/core/prompts/knowledge-extract.md`），**只有 1 个占位符**
/// `{{meeting_content}}`（由 [buildMeetingContent] 注入「会议信息头 + 逐字稿」）。
library;

import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/ids.dart';
import '../../core/log/log.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../engine/engine.dart';

/// 提示词资产路径。
const String kMinutesPromptAsset = 'assets/prompts/minutes.md';

/// 「说话人待定」占位 ID。
const String kPendingSpeakerIdText = 'spk_pending';

/// 加载提示词模板（带缓存；失败时抛出，由调用方降级）。
Future<String> loadMinutesTemplate() async {
  final String? cached = _cache;
  if (cached != null) return cached;
  final String text = await rootBundle.loadString(kMinutesPromptAsset);
  _cache = text;
  return text;
}

String? _cache;

/// 预置模板（供单测使用，避免依赖 Flutter binding）。
void setMinutesTemplateForTesting(String template) => _cache = template;

/// 清除模板缓存。
void clearMinutesTemplateCache() => _cache = null;

/// 解析片段展示名（复用 `minutesService.js` 的 `speakerNameOf` 语义）。
String speakerNameOf(Meeting meeting, TranscriptSegment segment) {
  final String? name = segment.speakerName;
  if (name != null && name.isNotEmpty) return name;
  if (segment.speakerId == kPendingSpeakerIdText) return '说话人待定';
  for (final speaker in meeting.speakers) {
    if (speaker.speakerId == segment.speakerId) return speaker.name;
  }
  final RegExpMatch? match = RegExp(r'^spk_(\d+)$').firstMatch(segment.speakerId);
  if (match != null) return '发言人${match.group(1)}';
  return segment.speakerId.isEmpty ? '未知' : segment.speakerId;
}

/// 把会议逐字稿渲染为 LLM 可消费的行式文本：`[mm:ss] 发言人N: 文本`。
String renderTranscriptMd(Meeting meeting) {
  return meeting.segments
      .map(
        (TranscriptSegment segment) =>
            '[${formatMs(segment.startTime)}] ${speakerNameOf(meeting, segment)}: ${segment.text}',
      )
      .join('\n');
}

/// 组装参会人对照表文本（`spk_1=张伟, spk_2=李娜`）。
String buildRosterText(List<SpeakerLike> speakers) {
  return speakers.map((SpeakerLike speaker) => '${speaker.speakerId}=${speaker.name}').join(', ');
}

/// 参会人的最小视图（便于纯函数单测）。
class SpeakerLike {
  /// 构造。
  const SpeakerLike({required this.speakerId, required this.name});

  /// 说话人 ID。
  final String speakerId;

  /// 展示名。
  final String name;
}

/// 会议元信息（Prompt 变量）。
class MeetingMeta {
  /// 构造元信息。
  const MeetingMeta({
    this.meetingTitle,
    this.meetingDate,
    this.duration,
    this.speakerCount,
    this.roster,
  });

  /// 会议标题。
  final String? meetingTitle;

  /// 会议日期（中文可读）。
  final String? meetingDate;

  /// 时长（`mm:ss`）。
  final String? duration;

  /// 参与人数。
  final int? speakerCount;

  /// 参会人对照表。
  final String? roster;
}

/// 组装 `{{meeting_content}}` 的注入内容：「会议信息头 + 逐字稿」。
///
/// 规则：仅当对应字段**非空**时才输出该标签行；所有元信息均缺失 → 退化为纯逐字稿。
String buildMeetingContent(String transcriptMd, MeetingMeta meta) {
  final List<String> lines = <String>[];
  if (meta.meetingTitle != null && meta.meetingTitle!.isNotEmpty) {
    lines.add('会议标题：${meta.meetingTitle}');
  }
  if (meta.meetingDate != null && meta.meetingDate!.isNotEmpty) {
    lines.add('会议时间：${meta.meetingDate}');
  }
  if (meta.duration != null && meta.duration!.isNotEmpty) {
    lines.add('会议时长：${meta.duration}');
  }
  // 参与人数为 0 视为「未知」→ 不输出（避免误导为“0 人参加”）。
  if (meta.speakerCount != null && meta.speakerCount != 0) {
    lines.add('参与人数：${meta.speakerCount} 人');
  }
  if (meta.roster != null && meta.roster!.isNotEmpty) {
    lines.add('参会人对照表：${meta.roster}');
  }
  if (lines.isEmpty) return transcriptMd;
  return '【会议信息】\n${lines.join('\n')}\n\n【逐字稿】\n$transcriptMd';
}

/// 变量插值（`{{meeting_content}}` 与 `{{transcript}}` 原样插入、不转义）。
String interpolate(String template, String transcriptMd, MeetingMeta meta) {
  return template
      .replaceFirst('{{meeting_title}}', meta.meetingTitle ?? '未命名会议')
      .replaceFirst('{{meeting_date}}', meta.meetingDate ?? '')
      .replaceFirst('{{duration}}', meta.duration ?? '')
      .replaceFirst('{{speaker_count}}', meta.speakerCount?.toString() ?? '')
      .replaceFirst('{{speaker_roster}}', meta.roster ?? '')
      .replaceFirst('{{meeting_content}}', buildMeetingContent(transcriptMd, meta))
      .replaceFirst('{{transcript}}', transcriptMd);
}

/// 由会议推导元信息（对应 `MinutesService._meta`）。
MeetingMeta metaOf(Meeting meeting) => MeetingMeta(
  meetingTitle: meeting.title,
  meetingDate: formatDateTimeCn(meeting.createdAt),
  duration: formatMs(meeting.durationMs),
  speakerCount: meeting.speakerCount,
  roster: buildRosterText(
    meeting.speakers
        .map((speaker) => SpeakerLike(speakerId: speaker.speakerId, name: speaker.name))
        .toList(growable: false),
  ),
);

/// 组装纪要对话消息：`[system, user]`（system 提示词与知识萃取取向一致）。
Future<List<LlmMessage>> buildMinutesMessages(
  Meeting meeting, {
  String? templateOverride,
}) async {
  final String template = templateOverride ?? await loadMinutesTemplate();
  final String transcriptMd = renderTranscriptMd(meeting);
  final MeetingMeta meta = metaOf(meeting);
  final String filled = interpolate(template, transcriptMd, meta);
  logDebug(
    'minutes',
    'Prompt 已组装',
    <String, Object?>{'meeting': meeting.id, 'chars': filled.length},
  );
  return <LlmMessage>[
    const LlmMessage(
      role: 'system',
      content:
          '你是一名资深知识管理专家、培训内容编辑和经验萃取顾问，严格按用户给定的 Markdown 格式输出结构化知识文档。',
    ),
    LlmMessage(role: 'user', content: filled),
  ];
}
