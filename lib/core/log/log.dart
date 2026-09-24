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
  if (weight < kLogLevelWeight[_currentLevel]!) return;
  final String stamp = DateTime.now().toUtc().toIso8601String();
  final String tail = extra == null ? '' : ' ${safeJson(extra)}';
  final String line = '[$stamp] ${level.toUpperCase()} [$scope] $msg$tail';
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
