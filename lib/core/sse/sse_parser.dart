/// `text/event-stream` 分帧器（移植 `dashscopeClient.js` 的 `iterateSse()`）。
///
/// 只负责分帧与 JSON 解析，**不做**业务映射；遇到 `data: [DONE]` 正常结束流。
library;

import 'dart:async';
import 'dart:convert';

/// 逐行解析 SSE 字节流为事件对象。
///
/// - 仅处理以 `data:` 开头的行；`event:` / `id:` / `:` 注释行被忽略；
/// - 空行（`\n\n`）表示一个事件的结束（本解析器按行处理，空行无副作用）；
/// - `data: [DONE]` → 立即结束（不 emit）；
/// - 无法解析为 JSON 的行被**忽略**（不抛错），与原 Node 版一致。
Stream<Map<String, dynamic>> parseSse(Stream<List<int>> byteStream) async* {
  final StringBuffer buffer = StringBuffer();
  await for (final List<int> chunk in byteStream) {
    buffer.write(utf8.decode(chunk, allowMalformed: true));
    final String text = buffer.toString();
    final List<String> lines = text.split('\n');
    // 最后一段可能是不完整的行，留到下一次。
    final String pending = lines.removeLast();
    for (final String rawLine in lines) {
      final Map<String, dynamic>? event = _parseLine(rawLine.trim());
      if (event == null) continue;
      if (event.containsKey(kSseDoneKey)) return; // data: [DONE]
      yield event;
    }
    buffer
      ..clear()
      ..write(pending);
  }
  // 流结束时处理残留的最后一行。
  final Map<String, dynamic>? tail = _parseLine(buffer.toString().trim());
  if (tail != null && !tail.containsKey(kSseDoneKey)) yield tail;
}

/// `[DONE]` 哨兵键（内部使用）。
const String kSseDoneKey = '__done__';

/// 解析单行 `data:` 载荷；返回 null 表示该行应被忽略。
///
/// 返回 `{kSseDoneKey: true}` 表示遇到 `[DONE]`（由 [parseSse] 结束流）。
Map<String, dynamic>? _parseLine(String line) {
  if (!line.startsWith('data:')) return null;
  final String payload = line.substring(5).trim();
  if (payload == '[DONE]') return const <String, dynamic>{kSseDoneKey: true};
  if (payload.isEmpty) return null;
  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

/// 从 SSE 事件对象里取出 `choices[0].delta.content`（只取正文，丢弃 `reasoning_content`）。
///
/// 返回 null 表示该事件不含正文增量。
String? sseDeltaContent(Map<String, dynamic> event) {
  final Object? choices = event['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final Object? first = choices[0];
  if (first is! Map<String, dynamic>) return null;
  final Object? delta = first['delta'];
  if (delta is! Map<String, dynamic>) return null;
  final Object? content = delta['content'];
  return content is String && content.isNotEmpty ? content : null;
}

/// 从 SSE 事件对象里取出 `choices[0].finish_reason`（可空）。
String? sseFinishReason(Map<String, dynamic> event) {
  final Object? choices = event['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final Object? first = choices[0];
  if (first is! Map<String, dynamic>) return null;
  final Object? reason = first['finish_reason'];
  return reason is String ? reason : null;
}
