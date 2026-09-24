/// 流扩展：节流（throttle）/ 批量（batch）/ 防抖（debounce）。
///
/// 替代原 web 端的 `useThrottledValue` 等 hook，供 Riverpod controller 使用。
library;

import 'dart:async';

/// 节流：每个 [interval] 内最多向下游转发一次最新值（首个值立即转发）。
///
/// 用于实时逐字稿的高频 upsert 事件，避免每秒 50 次重绘。
Stream<T> throttle<T>(Stream<T> source, Duration interval) {
  final StreamController<T> controller = StreamController<T>();
  Timer? timer;
  T? pending;
  bool hasPending = false;
  bool closed = false;
  DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void schedule() {
    timer?.cancel();
    final DateTime now = DateTime.now();
    final int elapsed = now.difference(lastEmit).inMicroseconds;
    final Duration wait = elapsed >= interval.inMicroseconds
        ? Duration.zero
        : Duration(microseconds: interval.inMicroseconds - elapsed);
    timer = Timer(wait, () {
      if (closed) return;
      if (hasPending) {
        final T value = pending as T;
        pending = null;
        hasPending = false;
        lastEmit = DateTime.now();
        controller.add(value);
      }
    });
  }

  final StreamSubscription<T> subscription = source.listen(
    (T event) {
      pending = event;
      hasPending = true;
      schedule();
    },
    onError: controller.addError,
    onDone: () {
      if (hasPending && !closed) {
        controller.add(pending as T);
      }
      timer?.cancel();
      if (!closed) controller.close();
    },
    cancelOnError: false,
  );

  controller.onCancel = () {
    closed = true;
    timer?.cancel();
    return subscription.cancel();
  };
  return controller.stream;
}

/// 批量：把 [interval] 窗口内到达的值收集为 **新的** `List` 后一次转发。
///
/// ⚠️ Riverpod 3 会用 `==` 比较新旧值，连续 emit 同一可变 List 实例会被过滤；
/// 本方法保证每次都构造新 List（另见 `unmodifiableCopy`）。
Stream<List<T>> batch<T>(Stream<T> source, Duration interval) {
  final StreamController<List<T>> controller = StreamController<List<T>>();
  final List<T> buffer = <T>[];
  Timer? timer;
  bool closed = false;

  void flush() {
    if (buffer.isEmpty) return;
    controller.add(List<T>.unmodifiable(buffer));
    buffer.clear();
  }

  final StreamSubscription<T> subscription = source.listen(
    buffer.add,
    onError: controller.addError,
    onDone: () {
      flush();
      timer?.cancel();
      if (!closed) controller.close();
    },
    cancelOnError: false,
  );

  timer = Timer.periodic(interval, (_) {
    if (!closed) flush();
  });

  controller.onCancel = () {
    closed = true;
    timer?.cancel();
    return subscription.cancel();
  };
  return controller.stream;
}

/// 防抖：静默 [interval] 后才转发最后一个值（用于标题自动保存）。
Stream<T> debounce<T>(Stream<T> source, Duration interval) {
  final StreamController<T> controller = StreamController<T>();
  Timer? timer;
  bool closed = false;

  final StreamSubscription<T> subscription = source.listen(
    (T event) {
      timer?.cancel();
      timer = Timer(interval, () {
        if (!closed) controller.add(event);
      });
    },
    onError: controller.addError,
    onDone: () {
      timer?.cancel();
      if (!closed) controller.close();
    },
    cancelOnError: false,
  );

  controller.onCancel = () {
    closed = true;
    timer?.cancel();
    return subscription.cancel();
  };
  return controller.stream;
}

/// 构造不可变副本（规避 Riverpod 3 的 `==` 过滤陷阱）。
List<T> unmodifiableCopy<T>(Iterable<T> source) => List<T>.unmodifiable(source);

/// 在原列表基础上追加一项并返回**新实例**（同上）。
List<T> appended<T>(List<T> source, T item) => <T>[...source, item];
