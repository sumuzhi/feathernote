/// `Result<T>`：成功（`Ok`）与失败（`Err`）的密封联合体。
///
/// 用于「错误是预期分支」的场景（如读盘、可选能力探测）；
/// 意外错误仍以抛 [AppError] 的形式上抛。
library;

import 'app_error.dart';

/// 结果的密封基类。
sealed class Result<T extends Object> {
  /// 构造结果（供子类使用）。
  const Result();

  /// 是否成功。
  bool get isOk => this is Ok<T>;

  /// 是否失败。
  bool get isErr => !isOk;

  /// 成功值时返回它，否则返回 [fallback]。
  T getOrElse(T fallback) => switch (this) {
    Ok<T>(:final T value) => value,
    Err<T>() => fallback,
  };

  /// 成功值时返回它，否则 null。
  T? getOrNull() => switch (this) {
    Ok<T>(:final T value) => value,
    Err<T>() => null,
  };

  /// 模式匹配：把两种分支都折叠为一个值。
  R fold<R>({required R Function(T value) onOk, required R Function(AppError error) onErr}) =>
      switch (this) {
        Ok<T>(:final T value) => onOk(value),
        Err<T>(:final AppError error) => onErr(error),
      };
}

/// 成功结果。
final class Ok<T extends Object> extends Result<T> {
  /// 构造成功结果。
  const Ok(this.value);

  /// 成功值。
  final T value;

  @override
  String toString() => 'Ok($value)';
}

/// 失败结果。
final class Err<T extends Object> extends Result<T> {
  /// 构造失败结果。
  const Err(this.error);

  /// 失败错误。
  final AppError error;

  @override
  String toString() => 'Err($error)';
}
