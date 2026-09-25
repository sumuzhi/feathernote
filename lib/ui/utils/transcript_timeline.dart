/// 转写页时间轴防呆工具。
///
/// 从网页端 `web/src/audio/timeline.ts` 1:1 迁移（Dart 化）。
/// 这三条常量 + 两个纯函数是「点最后一句不触发 ended」「末尾片段能正确高亮」的关键，
/// 也是与 SVG 设计稿一致的播放体验的基础。
library;

import '../../domain/segment.dart';

/// seek 上界余量：避免把 `currentTime` 正好 seek 到 `duration` 触发 ended。
const int kSeekEndMarginMs = 50;

/// 末尾闭合窗口：到音频末尾 [kTailActiveWindowMs] 以内时，
/// 当前高亮仍落在最后一段上，而不是"没有匹配段"。
const int kTailActiveWindowMs = 250;

/// 高亮命中容差：当前播放位置与该段 [startTime] 的差距在 [kActiveToleranceMs] 内
/// 即视为该段正在播放。
const int kActiveToleranceMs = 400;

/// 把目标 seek 位置夹取到合法范围。
///
/// - 下界 0；
/// - 上界 `durationMs - kSeekEndMarginMs`（防止正好落在 duration 触发 ended）。
int clampSeekMs(int targetMs, int durationMs) {
  if (durationMs <= 0) return 0;
  final int upper = durationMs - kSeekEndMarginMs;
  if (targetMs < 0) return 0;
  if (targetMs >= upper) return upper;
  return targetMs;
}

/// 根据当前播放位置找出应该高亮的 segment 下标。
///
/// 规则：
/// 1. 从最后一段往前找，当前位置落在 `[startTime - 容差, endTime]` 内即命中；
/// 2. 若当前位置在音频末尾 [kTailActiveWindowMs] 内，强制返回最后一段（末尾闭合）。
///
/// 返回 null 表示没有匹配段（比如 position 为 0 且没有任何一段开始于 0 附近）。
int? findActiveSegmentIndex(List<TranscriptSegment> segments, int currentMs, int durationMs) {
  if (segments.isEmpty) return null;
  final int last = segments.length - 1;

  // 末尾闭合。
  if (durationMs > 0 && currentMs >= durationMs - kTailActiveWindowMs) {
    return last;
  }

  for (int i = last; i >= 0; i--) {
    final TranscriptSegment seg = segments[i];
    final int start = seg.startTime - kActiveToleranceMs;
    final int end = seg.endTime;
    if (currentMs >= start && currentMs <= end) return i;
  }
  return null;
}
