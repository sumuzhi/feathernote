/// 音频帧去重与乱序接纳（**逐行移植** `server/src/core/chunkStore.js`）。
///
/// 以二进制帧头 `seq` 为唯一依据：重复帧直接忽略（补包重复帧不重复渲染），
/// 乱序帧照常接纳，并推进 `last_contiguous_seq` 水位；`last_time_ms` 取已见最大结束时间。
library;

/// 接纳一帧的结果。
class ChunkAcceptResult {
  /// 构造结果。
  const ChunkAcceptResult({required this.dup, required this.contiguous});

  /// 是否为重复帧。
  final bool dup;

  /// 当前连续水位。
  final int contiguous;
}

/// 会话态快照（供 `resume_state` 下发）。
class ChunkState {
  /// 构造快照。
  const ChunkState({
    required this.lastContiguousSeq,
    required this.lastTimeMs,
    required this.received,
  });

  /// 连续水位（从 -1 起，收到 seq=0 后变 0）。
  final int lastContiguousSeq;

  /// 已见最大结束时间（毫秒）。
  final int lastTimeMs;

  /// 已接纳的帧数。
  final int received;

  /// 转为 JSON（对应原 `resume_state` 字段）。
  Map<String, int> toJson() => <String, int>{
    'last_contiguous_seq': lastContiguousSeq,
    'last_time_ms': lastTimeMs,
    'received': received,
  };
}

/// 帧连续性追踪器。
class ChunkTracker {
  /// 已接纳的帧序号。
  final Set<int> seen = <int>{};

  /// 连续水位（从 -1 起）。
  int contiguous = -1;

  /// 已见最大结束时间（毫秒）。
  int maxTimeMs = 0;

  /// 接纳一帧。
  ChunkAcceptResult accept(int seq, int startMs, int endMs) {
    if (seen.contains(seq)) return ChunkAcceptResult(dup: true, contiguous: contiguous);
    seen.add(seq);
    while (seen.contains(contiguous + 1)) {
      contiguous += 1;
    }
    final int safeEnd = endMs;
    if (safeEnd > maxTimeMs) maxTimeMs = safeEnd;
    return ChunkAcceptResult(dup: false, contiguous: contiguous);
  }

  /// 导出恢复状态。
  ChunkState state() =>
      ChunkState(lastContiguousSeq: contiguous, lastTimeMs: maxTimeMs, received: seen.length);

  /// 重置（新会话复用实例时使用）。
  void reset() {
    seen.clear();
    contiguous = -1;
    maxTimeMs = 0;
  }
}
