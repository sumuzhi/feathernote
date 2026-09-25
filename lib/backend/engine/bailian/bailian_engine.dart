/// 百炼引擎：组合实时 ASR / 终稿 filetrans / LLM 三条链路为实现 [Engine]。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/log/log.dart';
import '../../../domain/segment.dart';
import '../engine.dart';
import 'filetrans.dart';
import 'llm.dart';
import 'realtime_asr.dart';

export 'realtime_asr.dart' show BailianRealtimeSession, RealtimeSocketFactory, RealtimeSocket, IoRealtimeSocket, RealtimeState, RealtimeTask, RealtimeHandlers;

/// 百炼引擎实现。
class BailianEngine implements Engine {
  /// 构造引擎（[dio] 可注入以便单测）。
  BailianEngine(this.cfg, {Dio? dio, this._socketFactory})
    : _filetrans = BailianFiletrans(cfg, dio: dio),
      _llm = BailianLlm(cfg, dio: dio);

  /// 冻结配置。
  final AppConfig cfg;

  /// 终稿链路。
  final BailianFiletrans _filetrans;

  /// LLM 链路。
  final BailianLlm _llm;

  /// WS 连接工厂（测试注入）。
  final RealtimeSocketFactory? _socketFactory;

  final Map<String, _SessionBinding> _sessions = <String, _SessionBinding>{};

  @override
  String get name => 'bailian';

  @override
  Stream<StreamEvent> startRealtimeSession({required String sessionId, required int sampleRate}) {
    final StreamController<StreamEvent> controller = StreamController<StreamEvent>.broadcast();
    final BailianRealtimeSession session = BailianRealtimeSession(
      cfg: cfg,
      sessionId: sessionId,
      meetingId: '',
      onEvent: controller.add,
      onError: (Object error) {
        logWarn('engine', '实时会话错误 session=$sessionId：$error');
        if (!controller.isClosed) controller.addError(error);
      },
      maxRestart: cfg.realtimeMaxRestart,
      socketFactory: _socketFactory,
    );
    _sessions[sessionId] = _SessionBinding(session: session, controller: controller);
    unawaited(
      session.open().catchError((Object error) {
        if (!controller.isClosed) controller.addError(error);
      }),
    );
    return controller.stream;
  }

  @override
  bool isRealtimeRunning(String sessionId) =>
      _sessions[sessionId]?.session.isRunning ?? false;

  @override
  bool feedRealtime(String sessionId, Uint8List pcm16le) {
    final _SessionBinding? binding = _sessions[sessionId];
    if (binding == null) return false;
    // 挂起态（暂停）不接受音频：任务已结束，避免字节堆进缓冲。
    if (binding.session.isSuspended) return false;
    binding.session.pushFrame(pcm16le);
    return binding.session.isRunning;
  }

  @override
  Future<void> stopRealtimeSession(String sessionId) async {
    final _SessionBinding? binding = _sessions.remove(sessionId);
    if (binding == null) return;
    await binding.session.flush();
    binding.session.close();
    await binding.controller.close();
  }

  @override
  Future<void> pauseRealtimeSession(String sessionId) async {
    final _SessionBinding? binding = _sessions[sessionId];
    if (binding == null) return;
    await binding.session.suspend();
  }

  @override
  Future<void> resumeRealtimeSession(String sessionId) async {
    final _SessionBinding? binding = _sessions[sessionId];
    if (binding == null) return;
    await binding.session.resume();
  }

  @override
  void abortRealtimeSession(String sessionId) {
    final _SessionBinding? binding = _sessions.remove(sessionId);
    if (binding == null) return;
    binding.session.close();
    unawaited(binding.controller.close());
  }

  @override
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true}) async {
    final String fileUrl =
        wavPathOrUrl.startsWith('oss://') || wavPathOrUrl.startsWith('http')
            ? wavPathOrUrl
            : await _filetrans.uploadLocalFile(wavPathOrUrl);
    return (await _filetrans.submitFiletrans(fileUrl, diarization: diarization)).taskId;
  }

  @override
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval}) async {
    final WaitResult waited = await _filetrans.waitTask(taskId, interval: interval);
    if (waited.status != 'SUCCEEDED' || waited.transcriptionUrl == null) {
      return FiletransResult(
        status: waited.status,
        segments: const <TranscriptSegment>[],
        error: 'filetrans 未成功（status=${waited.status}）',
      );
    }
    final Map<String, dynamic> raw = await _filetrans.downloadTranscription(waited.transcriptionUrl!);
    return FiletransResult(
      status: waited.status,
      segments: mapFiletransToSegments(raw),
      transcriptionUrl: waited.transcriptionUrl,
    );
  }

  @override
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) =>
      _llm.chatStream(messages, options: options);

  @override
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) =>
      _llm.chat(messages, options: options);

  @override
  Future<void> dispose() async {
    for (final String sessionId in _sessions.keys.toList(growable: false)) {
      abortRealtimeSession(sessionId);
    }
    _sessions.clear();
  }
}

/// 会话绑定（会话实例 + 事件控制器）。
class _SessionBinding {
  /// 构造绑定。
  const _SessionBinding({required this.session, required this.controller});

  /// 实时会话。
  final BailianRealtimeSession session;

  /// 事件控制器。
  final StreamController<StreamEvent> controller;
}
