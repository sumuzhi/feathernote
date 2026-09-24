/// 引擎抽象接口（对应原 `server/src/engine/index.js` 的 `AIEngine` 子集）。
///
/// UI / services 只依赖本接口，便于注入 `MockEngine` 做离线自测与单测。
library;

import 'dart:typed_data';

import '../../domain/segment.dart';

/// 终稿转写结果。
class FiletransResult {
  /// 构造终稿结果。
  const FiletransResult({required this.status, required this.segments, this.transcriptionUrl, this.error});

  /// 终态（`SUCCEEDED` / `FAILED` / `TIMEOUT`）。
  final String status;

  /// 解析后的片段列表（失败时为空）。
  final List<TranscriptSegment> segments;

  /// 结果 JSON 的下载 URL（成功时非空）。
  final String? transcriptionUrl;

  /// 失败原因（成功时为 null）。
  final String? error;

  /// 是否成功。
  bool get isSucceeded => status == 'SUCCEEDED';
}

/// LLM 对话消息（OpenAI 兼容）。
class LlmMessage {
  /// 构造消息。
  const LlmMessage({required this.role, required this.content});

  /// 角色：`system` / `user` / `assistant`。
  final String role;

  /// 内容。
  final String content;

  /// 转为 JSON。
  Map<String, String> toJson() => <String, String>{'role': role, 'content': content};
}

/// LLM 调用选项。
class LlmOptions {
  /// 构造选项（未指定的字段由 [AppConfig] 的默认值补齐）。
  const LlmOptions({
    this.temperature,
    this.maxTokens,
    this.topP,
    this.enableThinking,
    this.model,
  });

  /// 温度。
  final double? temperature;

  /// 单次输出上限（token）。
  final int? maxTokens;

  /// Top-P。
  final double? topP;

  /// 是否开启思考模式。
  final bool? enableThinking;

  /// 模型名覆盖。
  final String? model;
}

/// 引擎接口：百炼三条链路（实时 ASR / 终稿 filetrans / LLM）。
abstract class Engine {
  /// 引擎标识（日志用）。
  String get name;

  /// 开启实时识别会话，返回事件流；调用方负责 [feedRealtime] 喂音频。
  Stream<StreamEvent> startRealtimeSession({required String sessionId, required int sampleRate});

  /// 指定会话是否已「就绪」（已收到服务端 `task-started`，可接收音频）。
  ///
  /// 这是诊断「音频在收音但没有转写」的关键读数：为 false 时帧只会被缓冲，
  /// 不会有任何句子产出。
  bool isRealtimeRunning(String sessionId);

  /// 喂一包 PCM 到指定实时会话；返回是否实际发送。
  bool feedRealtime(String sessionId, Uint8List pcm16le);

  /// 收尾实时会话（发 `finish-task` 并等待 `task-finished`）。
  Future<void> stopRealtimeSession(String sessionId);

  /// 中止实时会话（不等待收尾）。
  void abortRealtimeSession(String sessionId);

  /// 提交终稿转写（异步任务），返回 taskId。
  ///
  /// [wavPathOrUrl] 本地 WAV 路径或 `oss://` / 公网 URL；
  /// [diarization] 说话人分离（字段名 `diarization_enabled`）。
  Future<String> submitFiletrans({required String wavPathOrUrl, bool diarization = true});

  /// 轮询直到终态，返回 [FiletransResult]。
  Future<FiletransResult> waitFiletrans(String taskId, {Duration? interval});

  /// 纪要流式生成：yield delta 文本。
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options});

  /// 非流式对话（兜底 / 单测）。
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options});

  /// 释放全部资源。
  Future<void> dispose();
}
