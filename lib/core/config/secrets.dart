/// 编译期注入的密钥（`--dart-define=KEY=VALUE`）。
///
/// 所有取值均通过 `String.fromEnvironment` 在编译期常量折叠：
/// release 构建里未注入的键为空串，**不会**把占位符打进产物。
library;

/// 编译期注入的密钥集合。
abstract final class Secrets {
  /// 百炼 API Key（`--dart-define=DASHSCOPE_API_KEY=sk-xxx`）。
  static const String dashscopeApiKey = String.fromEnvironment('DASHSCOPE_API_KEY');

  /// 百炼 Workspace ID（可选；配置后走专属域名）。
  static const String dashscopeWorkspaceId = String.fromEnvironment('DASHSCOPE_WORKSPACE_ID');

  /// 构建环境：`debug` | `release`。
  static const String buildEnv = String.fromEnvironment('BUILD_ENV', defaultValue: 'debug');

  /// 是否启用 debug-only 的本地 HTTP 适配层（`--dart-define=ENABLE_LOCAL_HTTP=true`）。
  static const bool enableLocalHttp = bool.fromEnvironment('ENABLE_LOCAL_HTTP', defaultValue: false);

  /// 是否强制使用 Mock 引擎（离线自测 / 单测）。
  static const bool useMockEngine = bool.fromEnvironment('MOCK', defaultValue: false);

  /// 日志级别覆盖（`--dart-define=LOG_LEVEL=debug`）。
  static const String logLevel = String.fromEnvironment('LOG_LEVEL', defaultValue: 'info');

  /// 本地 HTTP 调试端口。
  static const int localHttpPort = int.fromEnvironment('LOCAL_HTTP_PORT', defaultValue: 8787);

  /// 是否 release 构建（用于决定是否打印调试信息）。
  static bool get isRelease => buildEnv.toLowerCase() == 'release';
}
