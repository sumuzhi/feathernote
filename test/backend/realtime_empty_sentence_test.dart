/// 空句（服务端 `text` 为空的 `result-generated`）语义回归。
///
/// **历史 Bug**：只要不是「`sentence_begin` + 空文本」，其余空文本句也会
/// `revision++`、打印 `实时句子 id=1 ... text=""`、并发一个空 [StreamEvent]。
/// 现场日志看着像「正在转写」，实际服务端一句语音都没听到；连续 9 条空句后
/// 日志就再无输出，逐字稿被灌成空，会后终稿报 `ASR_RESPONSE_HAVE_NO_WORDS`。
///
/// 契约（本测试固化）：
/// - 空句**不是进度** → 零 `StreamEvent`、零 `实时句子` 日志、不推进 revision；
/// - 空句**必须立刻可见** → 第一条就要打告警（不等节流窗口）；
/// - 空句不污染后续正常句 → 正常句 revision 从 1 开始；
/// - 心跳不计入空句。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/engine/bailian/realtime_asr.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';
import 'package:smart_minutes_flutter/core/log/log.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';

/// 可控假 WS：自动回 `task-started`，可投放任意 `result-generated` 句子。
class _SentenceSocket implements RealtimeSocket {
  final StreamController<Object?> _in = StreamController<Object?>.broadcast();

  /// 已下发的音频包。
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  void sendText(String text) {
    if (text.contains('run-task')) {
      scheduleMicrotask(() => _raw(<String, dynamic>{
        'header': <String, dynamic>{'event': 'task-started'},
      }));
    }
  }

  @override
  void sendBytes(Uint8List bytes) => sent.add(bytes);

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void _raw(Map<String, dynamic> msg) {
    if (_in.isClosed) return;
    _in.add(jsonEncode(msg));
  }

  /// 投放一条 `result-generated`。
  void emitSentence({
    required int id,
    required String text,
    bool end = false,
    bool heartbeat = false,
    bool begin = false,
  }) {
    _raw(<String, dynamic>{
      'header': <String, dynamic>{'event': 'result-generated'},
      'payload': <String, dynamic>{
        'output': <String, dynamic>{
          'sentence': <String, dynamic>{
            'sentence_id': id,
            'text': text,
            'begin_time': 0,
            'end_time': 100,
            if (begin) 'sentence_begin': true,
            if (end) 'sentence_end': true,
            if (heartbeat) 'heartbeat': true,
          },
        },
      },
    });
  }
}

void main() {
  setUp(clearLogHistory);
  tearDown(clearLogHistory);

  /// 建一个已就绪（`task-started` 已收到）的会话。
  BailianRealtimeSession ready({
    required List<_SentenceSocket> sockets,
    required List<StreamEvent> events,
  }) {
    final BailianRealtimeSession session = BailianRealtimeSession(
      cfg: AppConfig.defaults(),
      sessionId: 's',
      meetingId: 'm',
      onEvent: events.add,
      onError: (_) {},
      maxRestart: 0,
      socketFactory: (String url, Map<String, dynamic> headers) async {
        final _SentenceSocket socket = _SentenceSocket();
        sockets.add(socket);
        return socket;
      },
      startTimeout: const Duration(seconds: 30),
    );
    return session;
  }

  test('连续 9 条空句：零 StreamEvent、零「实时句子」日志、计数为 9', () {
    fakeAsync((FakeAsync async) {
      final List<_SentenceSocket> sockets = <_SentenceSocket>[];
      final List<StreamEvent> events = <StreamEvent>[];
      final BailianRealtimeSession session = ready(sockets: sockets, events: events);

      session.open();
      async.flushMicrotasks();
      expect(session.isRunning, isTrue, reason: '已收到 task-started');

      for (int i = 1; i <= 8; i++) {
        sockets.single.emitSentence(id: 1, text: '');
      }
      sockets.single.emitSentence(id: 1, text: '', end: true);
      async.flushMicrotasks();

      expect(events, isEmpty, reason: '空句绝不能往逐字稿塞事件');
      expect(session.emptySentenceCount, 9);
      expect(
        dumpLogs(),
        isNot(contains('实时句子')),
        reason: '空句不得再伪装成转写进度打印「实时句子」',
      );
      expect(dumpLogs(), contains('服务端仅返回空句'), reason: '空句必须显式告警');
      expect(dumpLogs(), contains('句终但文本为空'), reason: '空句收尾需单独留痕');

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });

  test('第一条空句立刻告警（不等节流窗口）', () {
    fakeAsync((FakeAsync async) {
      final List<_SentenceSocket> sockets = <_SentenceSocket>[];
      final List<StreamEvent> events = <StreamEvent>[];
      final BailianRealtimeSession session = ready(sockets: sockets, events: events);

      session.open();
      async.flushMicrotasks();

      sockets.single.emitSentence(id: 1, text: '');
      async.flushMicrotasks();

      expect(
        dumpLogs(),
        contains('服务端仅返回空句 ×1'),
        reason: '第一条空句就要可见，否则现场日志仍然一片空白',
      );

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });

  test('空句不污染后续正常句：revision 从 1 开始且正常上屏', () {
    fakeAsync((FakeAsync async) {
      final List<_SentenceSocket> sockets = <_SentenceSocket>[];
      final List<StreamEvent> events = <StreamEvent>[];
      final BailianRealtimeSession session = ready(sockets: sockets, events: events);

      session.open();
      async.flushMicrotasks();

      // 先来 3 条空句（含 sentence_begin 型），再来一条真句子。
      sockets.single.emitSentence(id: 7, text: '', begin: true);
      sockets.single.emitSentence(id: 7, text: '');
      sockets.single.emitSentence(id: 7, text: '', end: true);
      async.flushMicrotasks();
      expect(events, isEmpty);

      sockets.single.emitSentence(id: 7, text: '今天的会议到此结束');
      async.flushMicrotasks();

      expect(events, hasLength(1));
      expect(events.single.text, '今天的会议到此结束');
      expect(
        events.single.revision,
        1,
        reason: '空句没推进过 revision → 首条真句子必须是 rev=1',
      );
      expect(dumpLogs(), contains('实时句子'), reason: '非空文本才是真正的句子');
      expect(session.emptySentenceCount, 3);

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });

  test('心跳不计入空句', () {
    fakeAsync((FakeAsync async) {
      final List<_SentenceSocket> sockets = <_SentenceSocket>[];
      final List<StreamEvent> events = <StreamEvent>[];
      final BailianRealtimeSession session = ready(sockets: sockets, events: events);

      session.open();
      async.flushMicrotasks();

      for (int i = 0; i < 5; i++) {
        sockets.single.emitSentence(id: 1, text: '', heartbeat: true);
      }
      async.flushMicrotasks();

      expect(session.emptySentenceCount, 0, reason: '心跳是链路保活信号，不是空句');
      expect(events, isEmpty);
      expect(dumpLogs(), isNot(contains('服务端仅返回空句')));

      session.close();
      async.elapse(const Duration(milliseconds: 10));
    });
  });
}
