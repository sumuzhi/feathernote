/// 业务错误码与 `AppError`（移植自 `server/src/shared.js` 的 `ERROR_CODE` / `BizError`
/// 与 `dashscopeClient.js` 的 `classifyStatus`）。
library;

/// 业务错误码（与原 Node 版数值逐字一致）。
enum ErrorCode {
  /// 成功。
  ok(0),

  /// 请求参数不合法。
  badRequest(1001),

  /// 资源不存在。
  notFound(2001),

  /// 引擎（百炼）错误。
  engineError(3001),

  /// 内部错误。
  internal(5000);

  /// 构造业务错误码。
  const ErrorCode(this.value);

  /// 数值编码。
  final int value;

  /// 由数值解析错误码，未命中返回 [ErrorCode.internal]。
  static ErrorCode fromValue(int value) {
    for (final ErrorCode code in ErrorCode.values) {
      if (code.value == value) return code;
    }
    return ErrorCode.internal;
  }
}

/// 带业务错误码的错误（服务层抛出，UI / debug 适配层统一转为可读提示）。
class AppError implements Exception {
  /// 构造业务错误。
  const AppError(this.code, this.message, {this.engineCode});

  /// 业务错误码。
  final ErrorCode code;

  /// 中文错误提示。
  final String message;

  /// 底层引擎错误码（如 `E_AUTH` / `E_TRUNCATED`），可为空。
  final String? engineCode;

  /// HTTP 状态码：401/403 → 鉴权；429 → 限流；413 → 过大；≥500 → 服务端；其余 → 通用。
  static String classifyStatus(int status) {
    if (status == 401 || status == 403) return 'E_AUTH';
    if (status == 429) return 'E_RATE_LIMIT';
    if (status == 413) return 'E_TOO_LARGE';
    if (status >= 500) return 'E_SERVER';
    return 'E_HTTP';
  }

  /// 由 HTTP 状态码构造引擎错误（错误码固定 [ErrorCode.engineError]）。
  factory AppError.fromStatus(int status, String message) {
    return AppError(ErrorCode.engineError, message, engineCode: classifyStatus(status));
  }

  @override
  String toString() => 'AppError(${code.value} ${code.name}): $message';
}
