/// 说话人展示信息解析：把 `speakerId` 映射为「展示名 + 配色 + 序号」。
///
/// 实时阶段说话人固定为 `spk_pending`（无分离），终稿回填后才出现 `spk_1…`，
/// 因此这里必须对两种 ID 都宽容。
library;

import '../../domain/segment.dart';
import '../../domain/speaker.dart';

/// 说话人展示信息。
class SpeakerView {
  /// 构造展示信息。
  const SpeakerView({
    required this.speakerId,
    required this.name,
    required this.colorIndex,
    required this.ordinal,
    required this.isPending,
  });

  /// 说话人 ID。
  final String speakerId;

  /// 展示名。
  final String name;

  /// 配色下标（0 起）。
  final int colorIndex;

  /// 序号（1 起，用于圆形徽标里的数字）。
  final int ordinal;

  /// 是否仍未定（实时阶段）。
  final bool isPending;
}

/// 解析说话人展示信息。
///
/// 优先级：`speakers` 表 → `segment.speakerName` → 由 `spk_N` 推导 → 兜底「说话人 1」。
SpeakerView speakerViewFor({
  required String speakerId,
  required List<Speaker> speakers,
  String? fallbackName,
}) {
  for (int i = 0; i < speakers.length; i++) {
    final Speaker speaker = speakers[i];
    if (speaker.speakerId == speakerId) {
      return SpeakerView(
        speakerId: speakerId,
        name: speaker.name,
        colorIndex: speaker.colorIndex,
        ordinal: i + 1,
        isPending: speakerId == kPendingSpeakerId,
      );
    }
  }
  final String displayName =
      (fallbackName != null && fallbackName.isNotEmpty) ? fallbackName : _deriveName(speakerId);
  return SpeakerView(
    speakerId: speakerId,
    name: displayName,
    colorIndex: _deriveColorIndex(speakerId),
    ordinal: _deriveOrdinal(speakerId),
    isPending: speakerId == kPendingSpeakerId,
  );
}

/// 为一组片段构造说话人表（用于页面在终稿尚未回填时的本地推导）。
List<Speaker> deriveSpeakers(List<TranscriptSegment> segments, {required String meetingId}) {
  final Map<String, int> order = <String, int>{};
  for (final TranscriptSegment segment in segments) {
    order.putIfAbsent(segment.speakerId, () => order.length);
  }
  return <Speaker>[
    for (final MapEntry<String, int> entry in order.entries)
      Speaker(
        meetingId: meetingId,
        speakerId: entry.key,
        name: _deriveName(entry.key),
        colorIndex: entry.value % 6,
        firstSeenMs: 0,
      ),
  ];
}

String _deriveName(String speakerId) {
  final int ordinal = _deriveOrdinal(speakerId);
  if (speakerId == kPendingSpeakerId) return '说话人 $ordinal';
  return '说话人 $ordinal';
}

int _deriveOrdinal(String speakerId) {
  final RegExpMatch? match = RegExp(r'(\d+)$').firstMatch(speakerId);
  if (match == null) return 1;
  final int? parsed = int.tryParse(match.group(1)!);
  if (parsed == null || parsed <= 0) return 1;
  return parsed;
}

int _deriveColorIndex(String speakerId) => (_deriveOrdinal(speakerId) - 1) % 6;
