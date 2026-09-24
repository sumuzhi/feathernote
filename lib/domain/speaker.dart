/// 说话人领域模型。
library;

/// 说话人（对应 `speakers` 表）。
class Speaker {
  /// 构造说话人。
  const Speaker({
    required this.meetingId,
    required this.speakerId,
    required this.name,
    required this.colorIndex,
    required this.firstSeenMs,
  });

  /// 所属会议 ID。
  final String meetingId;

  /// 说话人 ID（`spk_1` …）。
  final String speakerId;

  /// 展示名（默认 `发言人N`）。
  final String name;

  /// 配色下标（0–5）。
  final int colorIndex;

  /// 首次出现时间（毫秒）。
  final int firstSeenMs;

  /// 复制并替换部分字段。
  Speaker copyWith({
    String? meetingId,
    String? speakerId,
    String? name,
    int? colorIndex,
    int? firstSeenMs,
  }) {
    return Speaker(
      meetingId: meetingId ?? this.meetingId,
      speakerId: speakerId ?? this.speakerId,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      firstSeenMs: firstSeenMs ?? this.firstSeenMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Speaker &&
          other.meetingId == meetingId &&
          other.speakerId == speakerId &&
          other.name == name &&
          other.colorIndex == colorIndex &&
          other.firstSeenMs == firstSeenMs;

  @override
  int get hashCode => Object.hash(meetingId, speakerId, name, colorIndex, firstSeenMs);

  @override
  String toString() => 'Speaker($speakerId, $name, firstSeen=${firstSeenMs}ms)';
}
