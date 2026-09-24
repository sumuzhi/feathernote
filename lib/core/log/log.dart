/// 分级日志（debug / info / warn / error），格式 `[ISO] LEVEL [scope] msg {json}`。
///
/// 移植自原项目 `server/src/shared.js` 的 `log()` / `setLogLevel()` / `safeJson()`。
/// 不依赖任何业务模块，可被任意层引用。
library;

import 'dart:convert';

/// 日志级别权重（数值越大越严重）。
const Map<String, int> kLogLevelWeight = <String, int>{
  'debug': 10,
  'info': 20,
  'warn': 30,
  'error': 40,
};

/// 当前生效的日志级别（运行时可覆盖）。
String _currentLevel = 'info';

/// 覆盖日志级别（供测试与调试使用）；非法取值被忽略。
void setLogLevel(String level) {
  final String normalized = level.toLowerCase();
  if (kLogLevelWeight.containsKey(normalized)) {
    _currentLevel = normalized;
  }
}

/// 读取当前日志级别。
String get logLevel => _currentLevel;

/// 内存环形缓冲容量（供「导出诊断日志」）。
///
/// **不受日志级别过滤影响**：即使 `LOG_LEVEL=info`，debug 级日志也会进缓冲，
/// 这样用户导出的一次性诊断文件里信息是完整的。
const int kLogHistoryCapacity = 2000;

final List<String> _history = <String>[];

/// 已缓存的日志条数（测试 / 自检用）。
int get logHistoryLength => _history.length;

/// 读取最近日志（时间升序）；[limit] <= 0 表示全量。
List<String> recentLogs({int limit = 0}) {
  if (limit <= 0 || limit >= _history.length) {
    return List<String>.unmodifiable(_history);
  }
  return List<String>.unmodifiable(_history.sublist(_history.length - limit));
}

/// 导出用：把最近日志拼成一段文本。
String dumpLogs({int limit = 0}) => recentLogs(limit: limit).join('\n');

/// 清空历史缓冲（测试用）。
void clearLogHistory() => _history.clear();

/// 密钥脱敏：只保留前 4 位与长度，**绝不打印完整密钥**。
String maskSecret(String? value) {
  if (value == null || value.isEmpty) return '(empty)';
  if (value.length <= 4) return '****(len=${value.length})';
  return '${value.substring(0, 4)}****(len=${value.length})';
}

/// 该请求头是否属于敏感头（需要打码）。
bool isSecretHeader(String key) {
  final String k = key.toLowerCase();
  return k.contains('authorization') ||
      k.contains('api-key') ||
      k.contains('apikey') ||
      k.contains('accesskey') ||
      k.contains('signature') ||
      k.contains('token') ||
      k.contains('secret');
}

/// 请求头脱敏（`Authorization: Bearer sk-…` → `Bearer sk-a****(len=…)`）。
Map<String, Object?> redactHeaders(Map<String, Object?> headers) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in headers.entries)
      entry.key: _redactHeaderValue(entry.key, '${entry.value}'),
  };
}

String _redactHeaderValue(String key, String value) {
  if (!isSecretHeader(key)) return value;
  const String bearer = 'Bearer ';
  if (value.startsWith(bearer)) {
    return '$bearer${maskSecret(value.substring(bearer.length))}';
  }
  return maskSecret(value);
}

/// 安全 JSON 序列化（异常时不炸日志）。
String safeJson(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return value?.toString() ?? '';
  }
}

/// 结构化日志输出。
///
/// [level] 取值 debug / info / warn / error；[scope] 模块名（如 `asr`、`minutes`）；
/// [msg] 人读消息（中文）；[extra] 附加数据，序列化为 JSON。
void log(String level, String scope, String msg, [Object? extra]) {
  final int weight = kLogLevelWeight[level.toLowerCase()] ?? kLogLevelWeight['info']!;
  final String stamp = DateTime.now().toUtc().toIso8601String();
  final String tail = extra == null ? '' : ' ${safeJson(extra)}';
  final String line = '[$stamp] ${level.toUpperCase()} [$scope] $msg$tail';
  // 先入环形缓冲（不受级别过滤影响，保证「导出诊断日志」信息完整）。
  _history.add(line);
  if (_history.length > kLogHistoryCapacity) {
    _history.removeRange(0, _history.length - kLogHistoryCapacity);
  }
  if (weight < kLogLevelWeight[_currentLevel]!) return;
  // 直接写 stdout：Flutter 侧 `flutter logs` 与 logcat 均可看到。
  // ignore: avoid_print
  print(line);
}

/// debug 级别便捷方法。
void logDebug(String scope, String msg, [Object? extra]) => log('debug', scope, msg, extra);

/// info 级别便捷方法。
void logInfo(String scope, String msg, [Object? extra]) => log('info', scope, msg, extra);

/// warn 级别便捷方法。
void logWarn(String scope, String msg, [Object? extra]) => log('warn', scope, msg, extra);

/// error 级别便捷方法。
void logError(String scope, String msg, [Object? extra]) => log('error', scope, msg, extra);
