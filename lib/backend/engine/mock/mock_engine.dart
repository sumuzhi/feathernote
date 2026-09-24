/// 离线自测 / 单测用的 Mock 引擎（对应原 `server/src/engine/mock/MockEngine.js`）。
///
/// 行为确定性：不触网、不依赖随机时间；逐字稿按喂入的音频时长切固定句，
/// 终稿「立即成功」，LLM 输出可预测的字符串（便于断言）。
///
/// 启用方式：`--dart-define=MOCK=1`（或 `AppConfig.useMockEngine = true`）。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/ids.dart';
import '../../../core/log/log.dart';
import '../../../domain/segment.dart';
import '../engine.dart';

/// Mock 引擎。
class MockEngine implements Engine {
  /// 构造 Mock 引擎。
  MockEngine({
    this.sentenceMs = 3000,
    this.mockTaskIdPrefix = 'mock-task',
    this.llmReply = kDefaultMockReply,
  });

  /// 每句时长（毫秒）：按喂入音频时长切句。
  final int sentenceMs;

  /// 生成的 taskId 前缀。
  final String mockTaskIdPrefix;

  /// LLM 固定回复（流式按字符切分下发）。
  final String llmReply;

  /// 固定回复默认值。
  static const String kDefaultMockReply = '### 一、会议核心摘要\n\n（Mock 引擎生成的纪要）\n';

  final Map<String, _MockSession> _sessions = <String, _MockSession>{};

  @override
  String get name => 'mock';

  @override
  Stream<StreamEvent> startRealtimeSession({required String sessionId, required int sampleRate}) {
    final StreamController<StreamEvent> controller = StreamController<StreamEvent>.broadcast();
    _sessions[sessionId] = _MockSession(
      controller: controller,
      sentenceMs: sentenceMs,
      sampleRate: sampleRate,
    );
    logInfo('engine', 'Mock 实时会话已开启 session=$sessionId');
    return controller.stream;
  }

  @override
  bool isRealtimeRunning(String sessionId) => _sessions.containsKey(sessionId);

  @override
  bool feedRealtime(String sessionId, Uint8List pcm16le) {
    final _MockSession? session = _sessions[sessionId];
    if (session == null) return false;
    session.ms += (pcm16le.length ~/ 2) * 1000 ~/ session.sampleRate;
    _emitPending(session);
    return true;
  }

  @override
  Future<void> stopRealtimeSession(String sessionId) async {
    final _MockSession? session = _sessions.remove(sessionId);
    if (session == null) return;
    _emitPending(session, finalFlush: true);
    await session.controller.close();
  }

  @override
  void abortRealtimeSession(String sessionId) {
    final _MockSession? session = _sessions.remove(sessionId);
    if (session == null) return;
    unawaited(session.controller.close());
  }

  @override
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true}) async {
    return '$mockTaskIdPrefix-${genTaskId().substring(0, 8)}';
  }

  @override
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval}) async {
    // Mock 终稿：构造 2 个说话人、4 个片段的确定性结果。
    final List<TranscriptSegment> segments = <TranscriptSegment>[
      for (int i = 0; i < 4; i++)
        TranscriptSegment(
          meetingId: '',
          segmentId: 'seg_${i + 1}',
          ordinal: i,
          speakerId: 'spk_${(i % 2) + 1}',
          text: 'Mock 终稿第 ${i + 1} 句',
          startTime: i * 3000,
          endTime: (i + 1) * 3000,
          confidence: kFiletransConfidence,
          seqStart: i * 150,
          seqEnd: (i + 1) * 150 - 1,
        ),
    ];
    return FiletransResult(status: 'SUCCEEDED', segments: segments, transcriptionUrl: 'mock://$taskId');
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) async* {
    for (int i = 0; i < llmReply.length; i++) {
      yield llmReply[i];
      // 每 8 个字符让出一次事件循环，模拟真实流式节奏。
      if (i % 8 == 7) await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) async => llmReply;

  @override
  Future<void> dispose() async {
    for (final String id in _sessions.keys.toList(growable: false)) {
      abortRealtimeSession(id);
    }
    _sessions.clear();
  }

  /// 按已积累的音频时长补发句子（每 [sentenceMs] 一句）。
  void _emitPending(_MockSession session, {bool finalFlush = false}) {
    final int target = finalFlush ? (session.ms / sentenceMs).ceil() : (session.ms ~/ sentenceMs);
    while (session.emitted < target) {
      final int index = session.emitted;
      session.emitted += 1;
      session.controller.add(
        StreamEvent(
          segmentId: 'seg_${index + 1}',
          speakerId: kPendingSpeakerId,
          text: 'Mock 实时第 ${index + 1} 句',
          startTime: index * sentenceMs,
          endTime: (index + 1) * sentenceMs,
          isFinal: true,
          confidence: kFiletransConfidence,
          revision: 1,
        ),
      );
    }
  }
}

/// Mock 会话态。
class _MockSession {
  /// 构造会话态。
  _MockSession({required this.controller, required this.sentenceMs, required this.sampleRate});

  /// 事件控制器。
  final StreamController<StreamEvent> controller;

  /// 每句时长（毫秒）。
  final int sentenceMs;

  /// 采样率。
  final int sampleRate;

  /// 已积累的音频毫秒数。
  int ms = 0;

  /// 已发出的句子数。
  int emitted = 0;
}

/// 生成一段确定性的正弦波 PCM（供单测构造音频，无需真实麦克风）。
///
/// [durationMs] 时长，[sampleRate] 采样率，[freqHz] 频率。
Uint8List mockSinePcm({int durationMs = 1000, int sampleRate = 16000, double freqHz = 440}) {
  final int samples = (durationMs * sampleRate) ~/ 1000;
  final Int16List data = Int16List(samples);
  for (int i = 0; i < samples; i++) {
    final double t = i / sampleRate;
    data[i] = (math.sin(2 * math.pi * freqHz * t) * 12000).round();
  }
  final Uint8List bytes = Uint8List(samples * 2);
  for (int i = 0; i < samples; i++) {
    final int value = data[i];
    bytes[i * 2] = value & 0xff;
    bytes[i * 2 + 1] = (value >> 8) & 0xff;
  }
  return bytes;
}
