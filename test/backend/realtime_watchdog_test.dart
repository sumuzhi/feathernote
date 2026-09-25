/// 实时链路「静默 / 死链」取证与自愈回归。
///
/// 背景（用户现象）：录音继续、本地 PCM 照常，但**实时句子 ~3 秒后停止输出**，
/// 且日志里查不到任何「谁断了」的痕迹。两个历史黑洞：
/// 1. `_drain()` 在 `task.state != running` 时**静默**返回 → `_pending` 只进不出、一行日志都没有；
/// 2. `RealtimeTask._onClose()` 只把 state 置 closed **不触发重连** → 服务端静默关闭后链路永久僵死。
///
/// 契约（本测试固化）：
/// - `running` 下服务端长时间无任何消息 → **静默看门狗** warn（含 `_pending` 字节）+ 触发重连；
/// - 状态离开 `running` 且持续堆积 → **不再静默**：有限频 warn，且缓冲**不丢**（可计数/补发）；
/// - WS 关闭带 closeCode / closeReason 落日志。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/bailian/realtime_asr.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/core/log/log.dart';

/// 假墙钟基准（足够大，使「距上次事件 == 0 初始化」不会造成限频误判）。
const int _clockBase = 1000000000000;

/// 可完全控制的假 WS：可选自动回 `task-started`，可模拟服务端异常关闭。
class _ControllableSocket implements RealtimeSocket {
  _ControllableSocket({this.autoStarted = true});

  final bool autoStarted;
  final StreamController<Object?> _in = StreamController<Object?>.broadcast();

  /// 已发出的二进制包（用于断言「补发」）。
  final List<Uint8List> sent = <Uint8List>[];

  int? _code;
  String? _reason;

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  int? get closeCode => _code;

  @override
  String? get closeReason => _reason;

  @override
  void sendText(String text) {
    if (autoStarted && text.contains('run-task')) {
      scheduleMicrotask(() => _emit('task-started'));
    }
  }

  void _emit(String event) {
    if (_in.isClosed) return;
    _in.add(jsonEncode(<String, dynamic>{'header': <String, dynamic>{'event': event}}));
  }

  @override
  void sendBytes(Uint8List bytes) => sent.add(bytes);

  /// 模拟「服务端主动异常关闭」（带非 1000 关闭码）。
  Future<void> closeFromServer({int code = 1006, String reason = 'abnormal closure'}) async {
    _code = code;
    _reason = reason;
    if (!_in.isClosed) await _in.close();
  }

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

/// 一帧 20ms/640B 静音 PCM。
Uint8List _frame() => Uint8List(640);

BailianRealtimeSession _session({
  required int Function() nowMs,
  required RealtimeSocketFactory factory,
  int maxRestart = 3,
  Duration statsInterval = const Duration(seconds: 4),
  Duration silenceTimeout = const Duration(seconds: 18),
  Duration silenceWarnInterval = const Duration(seconds: 10),
  void Function(Object)? onError,
}) =>
    BailianRealtimeSession(
      cfg: AppConfig.defaults(),
      sessionId: 's',
      meetingId: 'm',
      onEvent: (_) {},
      onError: onError ?? (_) {},
      maxRestart: maxRestart,
      socketFactory: factory,
      startTimeout: const Duration(seconds: 30),
      statsInterval: statsInterval,
      silenceTimeout: silenceTimeout,
      silenceWarnInterval: silenceWarnInterval,
      nowMs: nowMs,
    );

void main() {
  setUp(clearLogHistory);
  tearDown(clearLogHistory);

  test('running 但服务端不再回任何消息 → 静默看门狗 warn + 触发重连', () {
    fakeAsync((FakeAsync async) {
      int clock = _clockBase;
      final List<_ControllableSocket> sockets = <_ControllableSocket>[];
      final BailianRealtimeSession session = _session(
        nowMs: () => clock,
        factory: (String url, Map<String, dynamic> headers) async {
          final _ControllableSocket socket = _ControllableSocket();
          sockets.add(socket);
          return socket;
        },
        statsInterval: const Duration(seconds: 1),
        silenceTimeout: const Duration(seconds: 2),
        silenceWarnInterval: const Duration(milliseconds: 1),
      );

      session.open();
      async.flushMicrotasks();
      expect(session.isRunning, isTrue, reason: '已收到 task-started');
      expect(sockets, hasLength(1));
      expect(session.serverMessageCount, 1, reason: 'task-started 应计入服务端消息');

      // 服务端从此**不再回任何消息**；时间推进到远超 2× 阈值（=4s）。
      clock += 6000;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      final String logs = dumpLogs();
      expect(logs, contains('发送统计'), reason: '必须有周期性发送统计行');
      expect(logs, contains('服务端静默'), reason: '静默必须显式告警（不再无声）');
      expect(
        sockets.length,
        greaterThanOrEqualTo(2),
        reason: '持续静默判定为链路僵死 → 必须重连（新开 run-task）',
      );
      expect(session.serverMessageCount, greaterThanOrEqualTo(1));

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });

  test('状态离开 running 且持续堆积 → 限频 warn（不再静默），缓冲不丢', () {
    fakeAsync((FakeAsync async) {
      final int clock = _clockBase;
      final List<_ControllableSocket> sockets = <_ControllableSocket>[];
      final BailianRealtimeSession session = _session(
        nowMs: () => clock,
        maxRestart: 0, // 不重连：停在失败态，专测「缓冲告警」
        statsInterval: const Duration(seconds: 1),
        factory: (String url, Map<String, dynamic> headers) async {
          final _ControllableSocket socket = _ControllableSocket();
          sockets.add(socket);
          return socket;
        },
      );

      session.open();
      async.flushMicrotasks();
      expect(session.isRunning, isTrue);

      // 服务端异常关闭 → 状态离开 running（带 closeCode）。
      sockets.single.closeFromServer(code: 1006, reason: 'server gone');
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 5));
      expect(session.isRunning, isFalse, reason: '连接已关闭');
      expect(dumpLogs(), contains('WS 连接被关闭'), reason: 'WS 关闭必须落日志');
      expect(dumpLogs(), contains('1006'), reason: '必须打出 closeCode');

      // 继续推音频（拾音未停）→ 必须被缓冲 + 限频 warn，绝不静默丢弃。
      for (int i = 0; i < 6; i++) {
        session.pushFrame(_frame());
      }
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(
        session.pendingBytes,
        greaterThanOrEqualTo(3200),
        reason: '缓冲不得被静默丢弃（pending 应持续累积）',
      );
      expect(
        dumpLogs(),
        contains('音频未下发'),
        reason: '「状态非 running 却堆积」必须告警（这是曾经的黑洞）',
      );
      expect(session.sentFrames, 0, reason: '状态非 running 时一个包都不应真正发出');

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });

  test('非正常关闭会自动重连，重连后缓冲按环形回放补发（数据不丢）', () {
    fakeAsync((FakeAsync async) {
      final int clock = _clockBase;
      final List<_ControllableSocket> sockets = <_ControllableSocket>[];
      final BailianRealtimeSession session = _session(
        nowMs: () => clock,
        statsInterval: const Duration(seconds: 1),
        factory: (String url, Map<String, dynamic> headers) async {
          final _ControllableSocket socket = _ControllableSocket();
          sockets.add(socket);
          return socket;
        },
      );

      session.open();
      async.flushMicrotasks();
      expect(session.isRunning, isTrue);

      // 第 1 个任务下发已录音频（10 帧 = 6400B）。
      for (int i = 0; i < 10; i++) {
        session.pushFrame(_frame());
      }
      async.elapse(const Duration(milliseconds: 5));
      expect(sockets.first.sent, isNotEmpty, reason: 'running 时应真实下发');
      final int sentBefore = session.sentFrames;
      expect(sentBefore, greaterThan(0));

      // 服务端异常关闭 → 应自动重连（新 socket）。
      unawaited(sockets.first.closeFromServer());
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 5));
      expect(sockets.length, greaterThanOrEqualTo(2), reason: '非正常关闭必须触发重连');

      // 新任务就绪后，缓冲/环形内容应被回放补发，且会话恢复 running。
      session.pushFrame(_frame());
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();
      expect(session.isRunning, isTrue, reason: '重连后应恢复 running');
      expect(
        sockets.last.sent,
        isNotEmpty,
        reason: '重连后必须把未发出/环形缓冲的音频补发，不得静默丢失',
      );

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });
}
