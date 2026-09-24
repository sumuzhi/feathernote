/// 会话态存储（内存）：一次录音会话的逐字稿片段（按 `segment_id` upsert）、
/// 说话人表、补包水位（`ChunkTracker`）、状态机。
///
/// **逐行移植** `server/src/services/sessionStore.js`：
/// - 片段一律**按 `segment_id` upsert**，绝不追加（补包不重复渲染、ID 跳变不闪屏）；
/// - `seq_start/seq_end` 由时间戳推导（`floor(start/20)` / `ceil(end/20)-1`），与终稿映射同规则；
/// - `replaceTranscript` 为**全量替换**（终稿回填）。
library;

import '../../../domain/segment.dart';
import '../../../domain/speaker.dart';
import '../algo/chunk_store.dart';

/// 单帧时长（毫秒），与前端契约一致。
const int kSessionFrameMs = 20;

/// 会话状态。
enum SessionStatus {
  /// 录音中。
  recording,

  /// 已停止。
  stopped,
}

/// 会话态。
class SessionState {
  /// 构造会话态。
  SessionState({
    required this.sessionId,
    required this.meetingId,
    required this.startedAtMs,
    required this.sampleRate,
  });

  /// 会话 ID。
  final String sessionId;

  /// 会议 ID。
  String meetingId;

  /// 标题。
  String title = '';

  /// 开始时间（epoch ms）。
  final int startedAtMs;

  /// 采样率（U1：实际采样率）。
  int sampleRate;

  /// 状态。
  SessionStatus status = SessionStatus.recording;

  /// 片段（`segment_id` → 片段）。
  final Map<String, TranscriptSegment> segments = <String, TranscriptSegment>{};

  /// 说话人表。
  List<Speaker> speakers = <Speaker>[];

  /// 帧连续性追踪器。
  final ChunkTracker tracker = ChunkTracker();
}

/// 由流式事件构造 / 更新片段。
///
/// [existing] 既有片段（用于保留 `seq_start` 与展示名）；[seq] 当前帧序号（可选）。
TranscriptSegment eventToSegment(StreamEvent event, {TranscriptSegment? existing, int? seq}) {
  final int startTime = event.startTime < 0 ? 0 : event.startTime;
  final int endTime = event.endTime > startTime ? event.endTime : startTime;
  final int seqStart = existing?.seqStart ?? (seq ?? (startTime ~/ kSessionFrameMs));
  final int seqEnd =
      seq != null
          ? (seq > seqStart ? seq : seqStart)
          : existing?.seqEnd ??
              (((endTime / kSessionFrameMs).ceil() - 1) > seqStart
                  ? ((endTime / kSessionFrameMs).ceil() - 1)
                  : seqStart);
  return TranscriptSegment(
    meetingId: existing?.meetingId ?? '',
    segmentId: event.segmentId,
    ordinal: existing?.ordinal ?? 0,
    speakerId: event.speakerId,
    speakerName: event.speakerName ?? existing?.speakerName,
    text: event.text,
    startTime: startTime,
    endTime: endTime,
    confidence: event.confidence,
    seqStart: seqStart,
    seqEnd: seqEnd,
  );
}

/// 归一化外来片段（HTTP `/stop` 请求体或终稿映射结果）为持久化字段集。
TranscriptSegment normalizeSegment(TranscriptSegment segment) {
  final int startTime = segment.startTime < 0 ? 0 : segment.startTime;
  final int endTime = segment.endTime > startTime ? segment.endTime : startTime;
  final int seqStart = segment.seqStart;
  final int ceilEnd = (endTime / kSessionFrameMs).ceil() - 1;
  final int seqEnd = segment.seqEnd > seqStart ? segment.seqEnd : (ceilEnd > seqStart ? ceilEnd : seqStart);
  return TranscriptSegment(
    meetingId: segment.meetingId,
    segmentId: segment.segmentId,
    ordinal: segment.ordinal,
    speakerId: segment.speakerId.isEmpty ? kPendingSpeakerId : segment.speakerId,
    speakerName: segment.speakerName,
    text: segment.text,
    startTime: startTime,
    endTime: endTime,
    confidence: segment.confidence,
    seqStart: seqStart,
    seqEnd: seqEnd,
  );
}

/// 会话态存储。
class SessionStore {
  /// 构造存储。
  SessionStore();

  final Map<String, SessionState> _sessions = <String, SessionState>{};

  /// 创建（或覆盖）会话态。
  SessionState create(
    String sessionId, {
    String meetingId = '',
    String title = '',
    int? startedAtMs,
    int sampleRate = 16000,
  }) {
    final SessionState state = SessionState(
      sessionId: sessionId,
      meetingId: meetingId,
      startedAtMs: startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      sampleRate: sampleRate,
    )..title = title;
    _sessions[sessionId] = state;
    return state;
  }

  /// 读取会话态。
  SessionState? get(String sessionId) => _sessions[sessionId];

  /// 取或建。
  SessionState getOrCreate(
    String sessionId, {
    String meetingId = '',
    String title = '',
    int? startedAtMs,
    int sampleRate = 16000,
  }) {
    return _sessions[sessionId] ??
        create(
          sessionId,
          meetingId: meetingId,
          title: title,
          startedAtMs: startedAtMs,
          sampleRate: sampleRate,
        );
  }

  /// 把流式事件 upsert 进会话逐字稿。
  TranscriptSegment? upsertSegment(String sessionId, StreamEvent event, {int? seq}) {
    final SessionState? state = _sessions[sessionId];
    if (state == null || event.segmentId.isEmpty) return null;
    final TranscriptSegment? existing = state.segments[event.segmentId];
    final TranscriptSegment segment = eventToSegment(event, existing: existing, seq: seq);
    state.segments[segment.segmentId] = segment.copyWith(
      meetingId: state.meetingId,
      ordinal: state.segments.length,
    );
    return state.segments[segment.segmentId];
  }

  /// 取有序逐字稿（按 `start_time` 升序）。
  List<TranscriptSegment> transcript(String sessionId) {
    final SessionState? state = _sessions[sessionId];
    if (state == null) return const <TranscriptSegment>[];
    final List<TranscriptSegment> list = state.segments.values.toList()
      ..sort(
        (TranscriptSegment a, TranscriptSegment b) {
          final int byTime = a.startTime.compareTo(b.startTime);
          return byTime != 0 ? byTime : a.segmentId.compareTo(b.segmentId);
        },
      );
    return list;
  }

  /// 全量替换逐字稿（终稿回填）。
  List<TranscriptSegment> replaceTranscript(String sessionId, List<TranscriptSegment> segments) {
    final SessionState? state = _sessions[sessionId];
    if (state == null) return const <TranscriptSegment>[];
    final List<TranscriptSegment> next = List<TranscriptSegment>.of(
      segments.map(normalizeSegment),
    )..sort(
        (TranscriptSegment a, TranscriptSegment b) {
          final int byTime = a.startTime.compareTo(b.startTime);
          return byTime != 0 ? byTime : a.segmentId.compareTo(b.segmentId);
        },
      );
    state.segments
      ..clear()
      ..addEntries(
        next.map((TranscriptSegment s) => MapEntry<String, TranscriptSegment>(s.segmentId, s)),
      );
    return next;
  }

  /// 设置说话人表。
  void setSpeakers(String sessionId, List<Speaker> speakers) {
    final SessionState? state = _sessions[sessionId];
    if (state != null) state.speakers = speakers;
  }

  /// 标记会话已停止。
  void markStopped(String sessionId) {
    final SessionState? state = _sessions[sessionId];
    if (state != null) state.status = SessionStatus.stopped;
  }

  /// 按会议 ID 查找会话态。
  SessionState? findByMeeting(String meetingId) {
    for (final SessionState state in _sessions.values) {
      if (state.meetingId == meetingId) return state;
    }
    return null;
  }

  /// 移除会话态。
  void remove(String sessionId) => _sessions.remove(sessionId);

  /// 清空（dispose 用）。
  void clear() => _sessions.clear();
}
