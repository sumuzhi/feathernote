/// 逐字稿片段与实时流事件。
library;

/// 逐字稿片段（对应 `transcript_segments` 表）。
class TranscriptSegment {
  /// 构造片段。
  const TranscriptSegment({
    required this.meetingId,
    required this.segmentId,
    required this.ordinal,
    required this.speakerId,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.confidence,
    required this.seqStart,
    required this.seqEnd,
    this.speakerName,
  });

  /// 所属会议 ID。
  final String meetingId;

  /// 片段 ID（会议内唯一）。
  final String segmentId;

  /// 排序序号（0 起）。
  final int ordinal;

  /// 说话人 ID。
  final String speakerId;

  /// 说话人展示名（可空 → 由 [speakerId] 推导）。
  final String? speakerName;

  /// 文本。
  final String text;

  /// 起始时间（毫秒）。
  final int startTime;

  /// 结束时间（毫秒）。
  final int endTime;

  /// 置信度（终稿恒为 0.9）。
  final double confidence;

  /// 起始帧序号。
  final int seqStart;

  /// 结束帧序号。
  final int seqEnd;

  /// 复制并替换部分字段。
  TranscriptSegment copyWith({
    String? meetingId,
    String? segmentId,
    int? ordinal,
    String? speakerId,
    String? speakerName,
    String? text,
    int? startTime,
    int? endTime,
    double? confidence,
    int? seqStart,
    int? seqEnd,
  }) {
    return TranscriptSegment(
      meetingId: meetingId ?? this.meetingId,
      segmentId: segmentId ?? this.segmentId,
      ordinal: ordinal ?? this.ordinal,
      speakerId: speakerId ?? this.speakerId,
      speakerName: speakerName ?? this.speakerName,
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      confidence: confidence ?? this.confidence,
      seqStart: seqStart ?? this.seqStart,
      seqEnd: seqEnd ?? this.seqEnd,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptSegment &&
          other.meetingId == meetingId &&
          other.segmentId == segmentId &&
          other.ordinal == ordinal &&
          other.speakerId == speakerId &&
          other.speakerName == speakerName &&
          other.text == text &&
          other.startTime == startTime &&
          other.endTime == endTime &&
          other.confidence == confidence &&
          other.seqStart == seqStart &&
          other.seqEnd == seqEnd;

  @override
  int get hashCode => Object.hash(
    meetingId,
    segmentId,
    ordinal,
    speakerId,
    speakerName,
    text,
    startTime,
    endTime,
    confidence,
    seqStart,
    seqEnd,
  );

  @override
  String toString() => 'TranscriptSegment($segmentId, $speakerId, ${startTime}ms, "$text")';
}

/// 实时转写下发的扁平事件（对应原 WS `transcript` 的 payload）。
class StreamEvent {
  /// 构造实时事件。
  const StreamEvent({
    required this.segmentId,
    required this.speakerId,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.isFinal,
    required this.confidence,
    this.speakerName,
    this.revision = 1,
  });

  /// 片段 ID（百炼侧为 `seg_<sentence_id>`）。
  final String segmentId;

  /// 说话人 ID（实时阶段恒为 `spk_pending`）。
  final String speakerId;

  /// 说话人展示名（可空）。
  final String? speakerName;

  /// 文本。
  final String text;

  /// 起始时间（毫秒）。
  final int startTime;

  /// 结束时间（毫秒）。
  final int endTime;

  /// 是否已成句（`sentence_end`）。
  final bool isFinal;

  /// 置信度。
  final double confidence;

  /// 句子修订号（同一 sentence_id 的第几次更新，1 起）。
  final int revision;

  @override
  String toString() => 'StreamEvent($segmentId, rev=$revision, final=$isFinal, "$text")';
}

/// 「说话人待定」占位 ID（实时阶段无说话人分离）。
const String kPendingSpeakerId = 'spk_pending';

/// 终稿映射用的常量置信度（百炼不返回逐句置信度）。
const double kFiletransConfidence = 0.9;
