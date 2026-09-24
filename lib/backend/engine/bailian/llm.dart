/// 百炼 LLM（OpenAI 兼容，SSE 流式）。
///
/// 移植 `dashscopeClient.js:739-829`。关键语义：
/// - **只消费 `choices[0].delta.content`**，思考模式的 `reasoning_content` 一律丢弃；
/// - `finish_reason == 'length'`（被 `max_tokens` 截断）**抛 [AppError]（`E_TRUNCATED`）**，
///   绝不静默返回残篇（否则残篇会被当成完整纪要写库）；
/// - LLM 聊天路径使用独立的**墙钟超时**（`llmTimeoutMs`），长纪要需要比全局 HTTP 超时更宽的预算。
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_error.dart';
import '../../../core/log/log.dart';
import '../../../core/sse/sse_parser.dart';
import '../engine.dart';

/// LLM 客户端（依赖可注入，单测不触网）。
class BailianLlm {
  /// 构造客户端。
  BailianLlm(this.cfg, {Dio? dio}) : _dio = dio ?? Dio();

  /// 冻结配置。
  final AppConfig cfg;

  /// HTTP 客户端。
  final Dio _dio;

  /// OpenAI 兼容端点。
  String get endpoint {
    final String base = cfg.llmBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/chat/completions';
  }

  /// 组装请求体（字段顺序与开关语义沿用原 Node 版）。
  Map<String, dynamic> buildBody(List<LlmMessage> messages, {LlmOptions? options, bool stream = true}) {
    final Map<String, dynamic> body = <String, dynamic>{
      'model': options?.model ?? cfg.llmModel,
      'messages': messages.map((LlmMessage m) => m.toJson()).toList(growable: false),
      'stream': stream,
      'temperature': options?.temperature ?? cfg.llmTemperature,
      'max_tokens': options?.maxTokens ?? cfg.llmMaxTokens,
    };
    final double? topP = options?.topP;
    if (topP != null) body['top_p'] = topP;
    // 思考开关：显式 opts 优先，其次配置；仅 boolean 才写入（避免下发 undefined 语义）。
    final bool? thinking = options?.enableThinking ?? cfg.llmEnableThinking;
    if (thinking != null) body['enable_thinking'] = thinking;
    return body;
  }

  /// 流式对话：yield delta 文本。
  Stream<String> chatStream(List<LlmMessage> messages, {LlmOptions? options}) async* {
    final Response<dynamic> resp = await _dio.post<dynamic>(
      endpoint,
      data: buildBody(messages, options: options, stream: true),
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${cfg.dashscopeApiKey}',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
        receiveTimeout: Duration(milliseconds: cfg.llmTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
      ),
    );
    final int status = resp.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw AppError.fromStatus(status, 'LLM 流式请求失败（HTTP $status）');
    }
    final Object? body = resp.data;
    if (body is! ResponseBody) {
      throw AppError(ErrorCode.engineError, 'LLM 流式响应缺少可读流', engineCode: 'E_PROTOCOL');
    }
    await for (final Map<String, dynamic> event in parseSse(body.stream)) {
      final String? delta = sseDeltaContent(event);
      if (delta != null) yield delta;
      final String? reason = sseFinishReason(event);
      if (reason == null) continue;
      if (reason == 'length') {
        // 被 max_tokens 截断：输出不完整，**不能静默 return**。
        throw AppError(
          ErrorCode.engineError,
          'LLM 输出被 max_tokens 截断（finish_reason=length），请上调 LLM_MAX_TOKENS',
          engineCode: 'E_TRUNCATED',
        );
      }
      return;
    }
  }

  /// 非流式对话（兜底 / 单测）。
  Future<String> chat(List<LlmMessage> messages, {LlmOptions? options}) async {
    final Response<dynamic> resp = await _dio.post<dynamic>(
      endpoint,
      data: buildBody(messages, options: options, stream: false),
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${cfg.dashscopeApiKey}',
          'Content-Type': 'application/json',
        },
        receiveTimeout: Duration(milliseconds: cfg.llmTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
      ),
    );
    final int status = resp.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw AppError.fromStatus(status, 'LLM 请求失败（HTTP $status）');
    }
    final Object? payload = resp.data;
    if (payload is! Map<String, dynamic>) {
      return '';
    }
    final Object? choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices[0] is Map<String, dynamic>) {
      final Object? message = (choices[0] as Map<String, dynamic>)['message'];
      if (message is Map<String, dynamic>) {
        final String? finish = (choices[0] as Map<String, dynamic>)['finish_reason'] as String?;
        if (finish == 'length') {
          logWarn('llm', '非流式对话被 max_tokens 截断');
        }
        return (message['content'] as String?) ?? '';
      }
    }
    return '';
  }
}
