/// 会议领域模型与历史列表投影。
library;

import '../core/ext/markdown_ext.dart';
import 'enums.dart';
import 'segment.dart';
import 'speaker.dart';

/// 会议（对应 `meetings` 表 + 子表聚合结果）。
class Meeting {
  /// 构造会议。
  const Meeting({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.sampleRate,
    required this.speakerCount,
    required this.status,
    required this.source,
    required this.finalizeStatus,
    required this.transcriptSource,
    required this.audioStatus,
    required this.audioBytes,
    required this.minutesPartial,
    required this.segments,
    required this.speakers,
    this.minutesMd,
    this.minutesError,
    this.finalizeError,
    this.audioKey,
    this.audioError,
  });

  /// 会议 ID。
  final String id;

  /// 标题。
  final String title;

  /// 创建时间。
  final DateTime createdAt;

  /// 时长（毫秒）。
  final int durationMs;

  /// 实际采样率（U1：请求 16000 可能被拒，写实际值）。
  final int sampleRate;

  /// 说话人数量。
  final int speakerCount;

  /// 纪要 Markdown（可空）。
  final String? minutesMd;

  /// 纪要是否为残篇（生成中断落盘）。
  final bool minutesPartial;

  /// 上次生成失败原因（成功为 null）。
  final String? minutesError;

  /// 会议状态。
  final MeetingStatus status;

  /// 来源。
  final MeetingSource source;

  /// 终稿状态。
  final FinalizeStatus finalizeStatus;

  /// 逐字稿来源。
  final TranscriptSource transcriptSource;

  /// 终稿失败原因（成功为 null）。
  final String? finalizeError;

  /// 音频归档状态。
  final AudioStatus audioStatus;

  /// 归档 key / 本地路径。
  final String? audioKey;

  /// 归档失败原因。
  final String? audioError;

  /// 音频字节数。
  final int audioBytes;

  /// 逐字稿片段（按 `startTime` 升序）。
  final List<TranscriptSegment> segments;

  /// 说话人表。
  final List<Speaker> speakers;

  /// 复制并替换部分字段。
  Meeting copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    int? durationMs,
    int? sampleRate,
    int? speakerCount,
    String? minutesMd,
    bool? minutesPartial,
    String? minutesError,
    MeetingStatus? status,
    MeetingSource? source,
    FinalizeStatus? finalizeStatus,
    TranscriptSource? transcriptSource,
    String? finalizeError,
    AudioStatus? audioStatus,
    String? audioKey,
    String? audioError,
    int? audioBytes,
    List<TranscriptSegment>? segments,
    List<Speaker>? speakers,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      durationMs: durationMs ?? this.durationMs,
      sampleRate: sampleRate ?? this.sampleRate,
      speakerCount: speakerCount ?? this.speakerCount,
      minutesMd: minutesMd ?? this.minutesMd,
      minutesPartial: minutesPartial ?? this.minutesPartial,
      minutesError: minutesError ?? this.minutesError,
      status: status ?? this.status,
      source: source ?? this.source,
      finalizeStatus: finalizeStatus ?? this.finalizeStatus,
      transcriptSource: transcriptSource ?? this.transcriptSource,
      finalizeError: finalizeError ?? this.finalizeError,
      audioStatus: audioStatus ?? this.audioStatus,
      audioKey: audioKey ?? this.audioKey,
      audioError: audioError ?? this.audioError,
      audioBytes: audioBytes ?? this.audioBytes,
      segments: segments ?? this.segments,
      speakers: speakers ?? this.speakers,
    );
  }

  /// 是否有可展示的纪要（非空且非残篇）。
  bool get hasMinutes => minutesMd != null && minutesMd!.trim().isNotEmpty && !minutesPartial;

  /// 投影为历史列表项（对应原 `persistence.js` 的 `toSummary`）。
  MeetingSummary toSummary() => MeetingSummary(
    id: id,
    title: title,
    createdAt: createdAt,
    durationMs: durationMs,
    speakerCount: speakerCount,
    status: status,
    finalizeStatus: finalizeStatus,
    hasMinutes: hasMinutes,
    minutesPartial: minutesPartial,
    minutesExcerpt: minutesExcerpt(minutesMd),
  );

  @override
  String toString() => 'Meeting($id, "$title", ${status.value}, seg=${segments.length})';
}

/// 历史列表用的轻量投影（对应 `toSummary`）。
class MeetingSummary {
  /// 构造历史列表项。
  const MeetingSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.speakerCount,
    required this.status,
    required this.finalizeStatus,
    required this.hasMinutes,
    required this.minutesPartial,
    this.minutesExcerpt = '',
  });

  /// 会议 ID。
  final String id;

  /// 标题。
  final String title;

  /// 创建时间。
  final DateTime createdAt;

  /// 时长（毫秒）。
  final int durationMs;

  /// 说话人数量。
  final int speakerCount;

  /// 会议状态。
  final MeetingStatus status;

  /// 终稿状态。
  final FinalizeStatus finalizeStatus;

  /// 是否已有完整纪要。
  final bool hasMinutes;

  /// 纪要是否为残篇。
  final bool minutesPartial;

  /// 纪要首行预览（空串表示无可展示摘要），供历史卡片第二行使用。
  final String minutesExcerpt;

  @override
  String toString() => 'MeetingSummary($id, "$title", ${status.value})';
}
