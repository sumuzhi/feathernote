/// 百炼实时流式 ASR（`RealtimeTask` 状态机 + `BailianRealtimeSession` 聚合）。
///
/// 移植 `dashscopeClient.js:450-682` 与 `realAdapters.js:99-411`。
/// 关键约束（复刻时不可走样）：
/// 1. 鉴权在**握手 HTTP 头**（`Authorization: Bearer <key>`）—— `dart:io` 的
///    `WebSocket.connect(url, headers: ...)` 原生支持，这是方案 B 相对 WebView 的决定性优势；
/// 2. 收到 `task-started` 后才可发音频；
/// 3. `task-failed` 会关连接且不可复用 → 重连必须**重开 run-task**（新 taskId，旧上下文作废）；
/// 4. `result-generated` 的 heartbeat 句要过滤；
/// 5. 向百炼下发按 **100ms / 3200B 聚合**（不是逐 640B 帧）；
/// 6. `text` 为空的 `result-generated` **不是转写进度**，而是服务端「没听到有效语音」的
///    信号 → 不产生 [StreamEvent]、不推进 revision，只累计并节流告警（见
///    [BailianRealtimeSession.emptySentenceCount]）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/config/app_config.dart';
import '../../../core/ids.dart';
import '../../../core/log/log.dart';
import '../../../core/ws_protocol.dart';
import '../../../domain/segment.dart';
import 'bailian_endpoints.dart';

/// 实时任务状态。
enum RealtimeState {
  /// 未启动。
  idle,

  /// 连接中。
  connecting,

  /// 就绪（已收到 `task-started`）。
  running,

  /// 收尾中（已发 `finish-task`）。
  finishing,

  /// 正常结束。
  finished,

  /// 任务失败。
  failed,

  /// 已关闭 / 已中止。
  closed,
}

/// 连接失败归类（便于一眼看出是 DNS / TLS / 鉴权 还是其它）。
String classifyConnectError(Object error) {
  if (error is HandshakeException) return 'TLS/SecureSocket 握手失败';
  if (error is SocketException) return '网络不可达 / DNS 解析失败 / 连接被拒';
  if (error is HttpException) return 'HTTP 握手被拒（多为鉴权 401/403 或域名错误）';
  if (error is WebSocketException) return 'WebSocket 协议异常';
  if (error is TimeoutException) return '连接超时';
  return '其他异常(${error.runtimeType})';
}

/// 日志用短文本（截断到 [max] 字符）。
String _shorten(String text, [int max = 60]) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

/// 携带可读原因的实时链路异常（`toString()` 即中文提示，UI/日志可直接展示）。
class RealtimeFailure implements Exception {
  /// 构造异常。
  RealtimeFailure(this.message);

  /// 可读原因。
  final String message;

  @override
  String toString() => message;
}

/// 实时任务启动超时：从发起连接到收到 `task-started` 的容忍上限。
///
/// 历史 Bug：握手后服务端**既不回 `task-started` 也不报错**时，会话会永远停在
/// `connecting`，音频帧只进 `_pending`，UI 却毫无反馈（「在收音但没有转写」）。
/// 超过该时长仍未就绪，即判定失败并显式上报。
const Duration kRealtimeStartTimeout = Duration(seconds: 10);

/// 实时链路**周期性发送统计**的间隔。
///
/// 这一行是「实时没输出」类问题的**决定性读数**：一眼区分
/// 「没在发（pending 堆积）」「发了但服务端不理（pending≈0、服务端消息年龄大）」
/// 「服务端在回但我们没上屏（有消息、有句子）」。
const Duration kAsrStatsInterval = Duration(seconds: 4);

/// 「状态非 running 却仍在堆积音频」告警的**限频**间隔。
const Duration kAsrBufferWarnInterval = Duration(seconds: 5);

/// 服务端静默看门狗：`running` 下超过该时长未收到**任何**服务端消息即告警。
const Duration kAsrSilenceTimeout = Duration(seconds: 18);

/// 静默告警的限频间隔（避免每个 tick 刷屏）。
const Duration kAsrSilenceWarnInterval = Duration(seconds: 10);

/// 空句（服务端返回 `text` 为空的句子）告警的**条数节流**：累计满这么多条再打一次。
const int kAsrEmptySentenceWarnBatch = 10;

/// 空句告警的**时间节流**窗口：距上次打印超过该时长即再打一次。
const Duration kAsrEmptySentenceWarnInterval = Duration(seconds: 5);

/// WebSocket 的最小抽象（便于单测注入替身，不触网）。
abstract class RealtimeSocket {
  /// 入站消息流（文本帧为 `String`）。
  Stream<Object?> get messages;

  /// 发送文本帧。
  void sendText(String text);

  /// 发送二进制帧。
  void sendBytes(Uint8List bytes);

  /// 关闭连接。
  Future<void> close();

  /// 关闭码（连接关闭**后**可读；未关闭 / 未知返回 null）。
  ///
  /// 服务端主动关闭（如配额 / 鉴权过期 / 被踢）时常带非 1000 的关闭码，
  /// 之前完全没记录 → 「实时忽然没输出」无从判断是谁断的。这里透出。
  int? get closeCode;

  /// 关闭原因（连接关闭后可用；未知返回 null）。
  String? get closeReason;
}

/// 基于 `dart:io` 的实现（握手可带自定义头 → 支持百炼的 Bearer 鉴权）。
class IoRealtimeSocket implements RealtimeSocket {
  /// 私有构造（由 [connect] 创建）。
  IoRealtimeSocket._(this._socket) : messages = _socket;

  /// 建立连接（带握手头）。
  static Future<IoRealtimeSocket> connect(String url, Map<String, dynamic> headers) async {
    final WebSocket socket = await WebSocket.connect(url, headers: headers);
    return IoRealtimeSocket._(socket);
  }

  final WebSocket _socket;

  @override
  final Stream<Object?> messages;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

  @override
  void sendText(String text) => _socket.add(text);

  @override
  void sendBytes(Uint8List bytes) => _socket.add(bytes);

  @override
  Future<void> close() => _socket.close();
}

/// 连接工厂（测试注入）。
typedef RealtimeSocketFactory = Future<RealtimeSocket> Function(
  String url,
  Map<String, dynamic> headers,
);

/// 实时任务的事件回调集合。
class RealtimeHandlers {
  /// 构造回调集合（任一回调可省略）。
  const RealtimeHandlers({
    this.onStarted,
    this.onSentence,
    this.onFinished,
    this.onFailed,
    this.onError,
    this.onServerMessage,
  });

  /// 收到 `task-started`。
  final void Function()? onStarted;

  /// 收到 `result-generated` 且非 heartbeat。
  final void Function(Map<String, dynamic> sentence, Map<String, dynamic> payload)? onSentence;

  /// 收到 `task-finished`。
  final void Function()? onFinished;

  /// 收到 `task-failed`。
  final void Function(String code, String message)? onFailed;

  /// 底层错误。
  final void Function(Object error)? onError;

  /// 收到**任意**服务端消息时回调：`(event, 是否 heartbeat)`。
  ///
  /// 含被过滤的 heartbeat 帧 —— 用于统计「服务端是否还在回话」与心跳数，
  /// 支撑静默看门狗与发送统计（这是判断「发了但服务端不理」的唯一依据）。
  final void Function(String event, bool heartbeat)? onServerMessage;
}

/// 百炼实时识别任务（低层，事件回调形式）。
///
/// ⚠️ 百炼 WS 是**任务语义**：`task-failed` 会关闭连接且不可复用；
/// 断线重连必须重新 `run-task` 开新任务。
class RealtimeTask {
  /// 构造实时任务。
  RealtimeTask(this.cfg, {required this.handlers, RealtimeSocketFactory? socketFactory})
    : taskId = genTaskId(),
      _socketFactory = socketFactory ?? IoRealtimeSocket.connect;

  /// 冻结配置。
  final AppConfig cfg;

  /// 事件回调。
  final RealtimeHandlers handlers;

  /// 本任务的 UUID。
  final String taskId;

  final RealtimeSocketFactory _socketFactory;

  final Completer<void> _finishedCompleter = Completer<void>();

  RealtimeSocket? _socket;
  StreamSubscription<Object?>? _subscription;

  /// 当前状态。
  RealtimeState state = RealtimeState.idle;

  /// 终结 Future（`task-finished` / `task-failed` / 关闭时结算）。
  Future<void> get finished => _finishedCompleter.future;

  /// 目标 WS URL。
  String get url => buildWsUrl(cfg);

  /// 建立连接并发送 `run-task`（收到 `task-started` 后方可发音频）。
  Future<void> start() async {
    if (state != RealtimeState.idle) return;
    state = RealtimeState.connecting;
    final Map<String, dynamic> headers = <String, dynamic>{
      'Authorization': 'Bearer ${cfg.dashscopeApiKey}',
      'user-agent': 'smart-minutes/${cfg.version}',
    };
    if (cfg.dashscopeWorkspaceId.isNotEmpty) {
      headers['X-DashScope-WorkSpace'] = cfg.dashscopeWorkspaceId;
    }
    try {
      logInfo(
        'asr',
        '发起实时连接（等待 task-started）',
        <String, Object?>{
          'task': taskId,
          'url': url,
          'model': cfg.realtimeModel,
          'region': cfg.bailianRegion,
          'sampleRate': cfg.realtimeSampleRate,
          'format': 'pcm',
          // Authorization 已按脱敏规则打码，**绝不打印完整 Key**。
          'headers': redactHeaders(headers),
        },
      );
      _socket = await _socketFactory(url, headers);
      logInfo('asr', 'WS 握手成功，等待 task-started task=$taskId');
    } catch (error) {
      state = RealtimeState.failed;
      // 连接阶段失败（DNS / TLS / 401 鉴权 / 域名错误）必须带上 URL 与分类，
      // 否则「音频在收音却没有转写」将无从定位。
      final String category = classifyConnectError(error);
      logWarn(
        'asr',
        '实时连接失败 task=$taskId 分类=$category url=$url '
        '原因=${error.runtimeType}: $error',
      );
      handlers.onError?.call(
        RealtimeFailure('连接失败（$category）：$error [url=$url]'),
      );
      _resolve();
      return;
    }
    _subscription = _socket!.messages.listen(
      _onMessage,
      onError: (Object error) {
        // WS 层错误必须留痕（此前只有 handlers 回调，无日志）。
        logWarn('asr', 'WS 错误 task=$taskId：${error.runtimeType}: $error');
        handlers.onError?.call(error);
      },
      onDone: _onClose,
      cancelOnError: false,
    );
    sendText(jsonEncode(buildRunTaskPayload(cfg, taskId)));
  }

  /// 组装 `run-task` 请求体（官方精确结构，字段名不可改）。
  static Map<String, dynamic> buildRunTaskPayload(AppConfig cfg, String taskId) {
    return <String, dynamic>{
      'header': <String, dynamic>{'action': 'run-task', 'task_id': taskId, 'streaming': 'duplex'},
      'payload': <String, dynamic>{
        'task_group': 'audio',
        'task': 'asr',
        'function': 'recognition',
        'model': cfg.realtimeModel,
        'parameters': <String, dynamic>{
          'format': 'pcm',
          'sample_rate': cfg.realtimeSampleRate,
          'semantic_punctuation_enabled': cfg.realtimeSemanticPunct,
          'max_sentence_silence': cfg.realtimeMaxSilenceMs,
          'heartbeat': cfg.realtimeHeartbeat,
          'language_hints': const <String>['zh', 'en'],
        },
        'input': <String, dynamic>{},
      },
    };
  }

  /// 解析服务端事件。
  void _onMessage(Object? data) {
    if (data is! String) return; // 忽略二进制帧。
    Map<String, dynamic> msg;
    try {
      final Object? decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return; // 无法解析的帧忽略。
    }
    final Object? header = msg['header'];
    if (header is! Map<String, dynamic>) return;
    final String? event = header['event'] as String?;
    // 任意服务端消息都留痕（含被过滤的 heartbeat）：这是静默看门狗与心跳计数的
    // 唯一依据，也是区分「服务端在回」与「服务端不理」的关键。
    handlers.onServerMessage?.call(event ?? 'unknown', _isHeartbeat(msg));
    switch (event) {
      case 'task-started':
        state = RealtimeState.running;
        // 关键：这条代表「实时会话真的起来了」，此后下发的音频才会被识别。
        logInfo('asr', '实时任务已就绪 task-started task=$taskId（此后可下发音频）');
        handlers.onStarted?.call();
        break;
      case 'result-generated':
        final Object? payload = msg['payload'];
        if (payload is! Map<String, dynamic>) break;
        final Object? output = payload['output'];
        if (output is! Map<String, dynamic>) break;
        final Object? sentence = output['sentence'];
        if (sentence is! Map<String, dynamic>) break;
        if (sentence['heartbeat'] == true) break;
        handlers.onSentence?.call(sentence, payload);
        break;
      case 'task-finished':
        state = RealtimeState.finished;
        logInfo('asr', '实时任务已结束 task-finished task=$taskId');
        handlers.onFinished?.call();
        _resolve();
        break;
      case 'task-failed':
        state = RealtimeState.failed;
        final String code = (header['error_code'] as String?) ?? WsError.engine;
        final String message = (header['error_message'] as String?) ?? '实时任务失败';
        // 服务端错误体（鉴权失败 / 模型不存在 / 参数非法）完整落日志，便于一击定位。
        logWarn(
          'asr',
          '实时任务失败 task=$taskId code=$code message=$message 原始=$data',
        );
        handlers.onFailed?.call(code, message);
        _resolve();
        break;
      default:
        // 未识别事件（含协议升级新增字段）留痕，但不打扰用户。
        logDebug('asr', '实时未识别事件 task=$taskId event=$event');
        break;
    }
  }

  /// 该消息是否为 heartbeat（`result-generated` → `payload.output.sentence.heartbeat`）。
  static bool _isHeartbeat(Map<String, dynamic> msg) {
    final Object? payload = msg['payload'];
    if (payload is! Map<String, dynamic>) return false;
    final Object? output = payload['output'];
    if (output is! Map<String, dynamic>) return false;
    final Object? sentence = output['sentence'];
    if (sentence is! Map<String, dynamic>) return false;
    return sentence['heartbeat'] == true;
  }

  /// 连接关闭：**显式记录关闭码 / 原因**（服务端主动关闭此前完全无日志）。
  void _onClose() {
    final RealtimeSocket? socket = _socket;
    final int? code = socket?.closeCode;
    final String? reason = socket?.closeReason;
    final bool abnormal = state != RealtimeState.finished && state != RealtimeState.failed;
    if (abnormal) state = RealtimeState.closed;
    if (socket == null) {
      // 由 [abort] 主动关闭（`_socket` 已置 null）→ 只留 info，避免误报「异常关闭」。
      logInfo('asr', 'WS 已主动关闭 task=$taskId state=${state.name}');
    } else if (abnormal) {
      logWarn(
        'asr',
        'WS 连接被关闭（非正常结束）task=$taskId state=${state.name} '
        'closeCode=${code ?? '—'} closeReason=${reason ?? '—'}',
      );
      // **链路已死**：必须走重启路径。否则 `_task.state` 停在非 running，
      // `_drain` 只缓冲不下发 → 录音继续、本地 PCM 照常，但实时句子永久静默。
      // 复用 `onFailed` → 会话侧 `_onTaskDown`（新 run-task + 环形回放 + 次数护栏）。
      handlers.onFailed?.call(
        'E_WS_CLOSED',
        'WS 连接被关闭（closeCode=${code ?? '—'} closeReason=${reason ?? '—'}）',
      );
    } else {
      logInfo(
        'asr',
        'WS 连接正常关闭 task=$taskId state=${state.name} '
        'closeCode=${code ?? '—'} closeReason=${reason ?? '—'}',
      );
    }
    _resolve();
  }

  /// 结算终结 Future（幂等）。
  void _resolve() {
    if (!_finishedCompleter.isCompleted) _finishedCompleter.complete();
  }

  /// 发送文本帧。
  void sendText(String text) {
    try {
      _socket?.sendText(text);
    } catch (error) {
      handlers.onError?.call(error);
    }
  }

  /// 发送一包 PCM 音频；仅在 [RealtimeState.running] 时有效。
  bool sendAudio(Uint8List pcm16le) {
    if (state != RealtimeState.running) return false;
    try {
      _socket?.sendBytes(pcm16le);
      return true;
    } catch (error) {
      handlers.onError?.call(error);
      return false;
    }
  }

  /// 主动收尾：发送 `finish-task`。
  void finish() {
    if (state == RealtimeState.running || state == RealtimeState.connecting) {
      sendText(
        jsonEncode(<String, dynamic>{
          'header': <String, dynamic>{'action': 'finish-task', 'task_id': taskId, 'streaming': 'duplex'},
          'payload': <String, dynamic>{'input': <String, dynamic>{}},
        }),
      );
      state = RealtimeState.finishing;
    }
  }

  /// 立即中止（关闭底层连接）。
  void abort() {
    state = RealtimeState.closed;
    final RealtimeSocket? socket = _socket;
    _socket = null;
    try {
      unawaited(_subscription?.cancel());
      unawaited(socket?.close());
    } catch (_) {
      // 忽略关闭异常。
    }
    _subscription = null;
    _resolve();
  }
}

/// 百炼实时会话：把 20ms/640B 帧聚合成 100ms/3200B 下发，
/// 并把 `result-generated` 句子映射为 [StreamEvent]。
class BailianRealtimeSession {
  /// 构造会话。
  BailianRealtimeSession({
    required this.cfg,
    required this.sessionId,
    required this.meetingId,
    required this.onEvent,
    required this.onError,
    this.maxRestart = 3,
    this.socketFactory,
    this.startTimeout = kRealtimeStartTimeout,
    this.statsInterval = kAsrStatsInterval,
    this.silenceTimeout = kAsrSilenceTimeout,
    this.silenceWarnInterval = kAsrSilenceWarnInterval,
    int Function()? nowMs,
  }) : chunkBytes = ((cfg.realtimeFrameMs / 1000) * cfg.realtimeSampleRate).round() * 2,
       ringBytes = ((cfg.realtimeRingMs / 1000) * cfg.realtimeSampleRate).round() * 2,
       _now = nowMs ?? _wallClockMs;

  /// 墙钟毫秒（默认时钟；单测可注入可控时钟）。
  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  /// 冻结配置。
  final AppConfig cfg;

  /// 会话 ID。
  final String sessionId;

  /// 会议 ID。
  final String meetingId;

  /// 事件回调（每句一个 [StreamEvent]）。
  final void Function(StreamEvent event) onEvent;

  /// 错误回调。
  final void Function(Object error) onError;

  /// 最大重启次数（超出后不再重开，交给会后终稿兜底）。
  final int maxRestart;

  /// 连接工厂（测试注入）。
  final RealtimeSocketFactory? socketFactory;

  /// 启动超时（收到 `task-started` 的容忍上限；单测可缩短）。
  final Duration startTimeout;

  /// 发送统计 / 静默看门狗的**执行间隔**（单测可缩短）。
  final Duration statsInterval;

  /// 服务端静默阈值：`running` 下超过该时长无任何服务端消息即视为异常（单测可缩短）。
  final Duration silenceTimeout;

  /// 静默告警的限频间隔（单测可缩短）。
  final Duration silenceWarnInterval;

  /// 时钟（默认墙钟；单测注入可控时钟，便于断言看门狗）。
  final int Function() _now;

  /// 向百炼单次下发的字节数（100ms@16k 单声道 16bit = 3200B）。
  final int chunkBytes;

  /// 环形缓冲字节上限（默认 30s，供断线回放）。
  final int ringBytes;

  final List<int> _pending = <int>[];
  final List<Uint8List> _ring = <Uint8List>[];
  int _ringBytesTotal = 0;
  final Map<int, int> _revById = <int, int>{};

  RealtimeTask? _task;
  Timer? _startTimer;
  Timer? _statsTimer;
  bool _closed = false;
  bool _finishing = false;
  bool _suspended = false;
  bool _restarted = false;
  int _restartCount = 0;

  /// 是否处于挂起态（暂停：任务已结束、连接已断，等待恢复重开）。
  bool get isSuspended => _suspended;

  /// 累计成功下发的音频帧数 / 字节数。
  int sentFrames = 0;
  int sentBytes = 0;

  /// 累计收到的服务端消息数（含 heartbeat）与心跳帧数。
  int serverMessageCount = 0;
  int heartbeatCount = 0;

  /// 最近一次收到服务端消息的时钟毫秒（0 = 尚未收到任何消息）。
  int lastServerMsgAtMs = 0;

  int _lastBufferWarnAtMs = 0;
  int _lastSilenceWarnAtMs = 0;
  int _lastSilencePendingBytes = -1;

  /// 累计收到的**空文本**句子数（`text.trim().isEmpty` 且非心跳）。
  ///
  /// 这是「服务端有没有听到语音」的**唯一诚实读数**：有语音时百炼会回吐逐步增长的
  /// 非空文本；持续返回空句 = 服务端认为当前没有有效语音信号。
  int _emptySentenceCount = 0;

  /// 空句计数对外只读出口（供测试与诊断断言）。
  int get emptySentenceCount => _emptySentenceCount;

  int _lastEmptyWarnAtMs = 0;
  int _lastEmptyWarnCount = 0;

  /// 尚未下发的缓冲字节数（诊断 / 测试：判断链路是否「堵住」）。
  int get pendingBytes => _pending.length;

  /// 最近一次失败原因（诊断用；成功启动后清空）。
  String? lastError;

  /// 会议时钟（已推送的音频毫秒数）。
  int meetingClockMs = 0;

  /// 新任务的时间基准（重启时补偿，避免时间戳整体后移）。
  int taskBaseMs = 0;

  /// 是否已就绪（可发音频）。
  bool get isRunning => _task?.state == RealtimeState.running;

  /// 建立（或重建）百炼任务。
  Future<void> open() async {
    if (_closed || _task != null) return;
    // 新任务上下文：空句读数必须归零，否则重启后计数会跨任务累计而失真。
    _resetEmptySentenceStats();
    final RealtimeTask task = RealtimeTask(
      cfg,
      handlers: RealtimeHandlers(
        onStarted: _onStarted,
        onSentence: (Map<String, dynamic> sentence, Map<String, dynamic> payload) =>
            _onSentence(sentence),
        onFinished: () => logInfo('asr', '实时任务已结束 session=$sessionId'),
        onFailed: (String code, String message) => unawaited(_onTaskDown(code, message)),
        onError: onError,
        onServerMessage: _onServerMessage,
      ),
      socketFactory: socketFactory,
    );
    _task = task;
    // 启动看门狗：握手后若迟迟不 `task-started`（服务端静默 / 连接被静默关闭），
    // 到点即判失败并上报，避免音频帧无声无息地堆在 `_pending` 里。
    _startTimer?.cancel();
    _startTimer = Timer(startTimeout, _onStartTimeout);
    // 周期发送统计 + 服务端静默看门狗（只起一个 Timer，close 时统一取消）。
    _statsTimer ??= Timer.periodic(statsInterval, (Timer _) => _tickDiagnostics());
    await task.start();
  }

  /// 启动超时：仍未就绪即判失败（含连接被静默关闭的情形）。
  void _onStartTimeout() {
    _startTimer = null;
    final RealtimeTask? task = _task;
    if (_closed || _finishing) return;
    // 已就绪 / 已经明确失败（连接失败或 task-failed 已上报）→ 不重复告警。
    if (task == null ||
        task.state == RealtimeState.running ||
        task.state == RealtimeState.failed) {
      return;
    }
    final String reason =
        '实时转写连接超时（${startTimeout.inSeconds}s 内未就绪，state=${task.state.name}）';
    lastError = reason;
    logWarn('asr', '$reason url=${task.url} session=$sessionId');
    onError(RealtimeFailure('$reason，请依赖会后终稿'));
    // 中止这条无望的连接；后续帧不再尝试下发（已在 UI 明确告知）。
    task.abort();
  }

  /// 任务就绪：置运行态；重连时先回放环形缓冲，再接管新帧。
  void _onStarted() {
    // 已就绪 → 撤下启动看门狗。
    _startTimer?.cancel();
    _startTimer = null;
    lastError = null;
    // 新任务就绪 → 复位静默基线（避免拿旧任务的时间误判静默）。
    _lastSilencePendingBytes = -1;
    _lastSilenceWarnAtMs = 0;
    if (_restarted && _ring.isNotEmpty) {
      final BytesBuilder replay = BytesBuilder(copy: false);
      for (final Uint8List chunk in _ring) {
        replay.add(chunk);
      }
      final Uint8List bytes = replay.takeBytes();
      for (int offset = 0; offset < bytes.length; offset += chunkBytes) {
        final int end = (offset + chunkBytes > bytes.length) ? bytes.length : offset + chunkBytes;
        _task?.sendAudio(Uint8List.sublistView(bytes, offset, end));
      }
      logInfo(
        'asr',
        '重连回放环形缓冲 session=$sessionId 字节=${bytes.length}B 覆盖=${ringDurationMs()}ms',
      );
    }
    _restarted = false;
    _drain();
    logInfo('asr', '实时任务已就绪 session=$sessionId meeting=$meetingId（开始下发音频）');
  }

  /// 收到任意服务端消息（含 heartbeat）：刷新「服务端是否还在回话」的读数。
  void _onServerMessage(String event, bool heartbeat) {
    serverMessageCount++;
    lastServerMsgAtMs = _now();
    if (heartbeat) heartbeatCount++;
  }

  /// 周期诊断（每 [statsInterval]）：**一行说清**「在不在发 / 服务端理不理 / 堵没堵」。
  void _tickDiagnostics() {
    if (_closed) return;
    final RealtimeTask? task = _task;
    if (task == null) return;
    logInfo(
      'asr',
      '发送统计 session=$sessionId state=${task.state.name} '
      'pending未发送=${_pending.length}B 已发帧=$sentFrames 已发=${sentBytes}B '
      '距服务端消息=${_serverMsgAgeLabel()} 服务端消息=$serverMessageCount '
      '心跳=$heartbeatCount 重连=$_restartCount/$maxRestart running=$isRunning',
    );
    _checkServerSilence(task);
  }

  /// 「距上次收到服务端消息」的可读标签。
  String _serverMsgAgeLabel() {
    if (lastServerMsgAtMs == 0) return '从未收到';
    final int age = _now() - lastServerMsgAtMs;
    return age < 0 ? '0ms' : '${age}ms';
  }

  /// 服务端静默看门狗：`running` 下长时间收不到任何服务端消息即告警；
  /// 持续静默（或缓冲同时增长）→ 判定链路僵死，**复用 `_onTaskDown` 重启**。
  void _checkServerSilence(RealtimeTask task) {
    if (_closed || _finishing) return;
    if (task.state != RealtimeState.running) return;
    if (lastServerMsgAtMs == 0) return; // 还没收到过任何消息 → 交给启动超时兜底
    final int now = _now();
    final int silentMs = now - lastServerMsgAtMs;
    if (silentMs < silenceTimeout.inMilliseconds) {
      // 有消息 / 未达阈值 → 复位。
      _lastSilencePendingBytes = -1;
      _lastSilenceWarnAtMs = 0;
      return;
    }
    final bool growing =
        _lastSilencePendingBytes >= 0 && _pending.length > _lastSilencePendingBytes;
    _lastSilencePendingBytes = _pending.length;
    // 硬阈值：静默持续到 2× 阈值仍无任何消息 → 即便缓冲未增长也判死（心跳默认开启，
    // 真正健康的链路不会这么久一句 heartbeat 都没有）。
    final bool dead = growing || silentMs >= silenceTimeout.inMilliseconds * 2;
    if (now - _lastSilenceWarnAtMs >= silenceWarnInterval.inMilliseconds) {
      _lastSilenceWarnAtMs = now;
      logWarn(
        'asr',
        '服务端静默 ${silentMs}ms（>${silenceTimeout.inSeconds}s）session=$sessionId '
        'state=${task.state.name} pending未发送=${_pending.length}B 未发送帧=${_pending.length ~/ chunkBytes} '
        '已发帧=$sentFrames 心跳=$heartbeatCount '
        '缓冲${growing ? '持续增长→判定链路僵死' : '未增长'}'
        '${dead ? '，触发重连' : '（继续观察）'}',
      );
    }
    if (dead) {
      _lastSilencePendingBytes = -1;
      unawaited(
        _onTaskDown(
          'E_SILENT',
          '服务端 ${silentMs}ms 无任何消息${growing ? '且缓冲持续增长' : ''}',
        ),
      );
    }
  }

  /// 状态非 running 却仍在堆积 → 限频 warn（明确「因状态非 running 而缓冲」，绝不静默）。
  void _maybeWarnBuffering(RealtimeTask task) {
    final int now = _now();
    if (now - _lastBufferWarnAtMs < kAsrBufferWarnInterval.inMilliseconds) return;
    _lastBufferWarnAtMs = now;
    logWarn(
      'asr',
      '音频未下发（缓冲中，未丢）session=$sessionId 因状态非 running：'
      'state=${task.state.name} pending=${_pending.length}B 未发送帧=${_pending.length ~/ chunkBytes} '
      '（重连成功后按环形缓冲回放）',
    );
  }

  /// 把累积的 PCM 凑满 [chunkBytes] 后下发。
  ///
  /// **不再静默**：
  /// - 状态非 running 却仍在堆积 → 限频 warn（[_maybeWarnBuffering]）；
  /// - 发送失败（状态在循环中变化 / socket 异常）→ **把该包放回队首**（绝不丢），退出。
  void _drain() {
    final RealtimeTask? task = _task;
    if (task == null) return;
    if (task.state != RealtimeState.running) {
      if (_pending.length >= chunkBytes) _maybeWarnBuffering(task);
      return;
    }
    while (_pending.length >= chunkBytes) {
      final Uint8List chunk = Uint8List.fromList(_pending.sublist(0, chunkBytes));
      _pending.removeRange(0, chunkBytes);
      if (task.sendAudio(chunk)) {
        sentFrames++;
        sentBytes += chunk.length;
      } else {
        // 发送未成功 → 放回队首，绝不静默丢弃。
        _pending.insertAll(0, chunk);
        _maybeWarnBuffering(task);
        break;
      }
    }
  }

  /// 追加 PCM 到有界环形缓冲。
  void _appendRing(Uint8List pcm) {
    _ring.add(pcm);
    _ringBytesTotal += pcm.length;
    while (_ringBytesTotal > ringBytes && _ring.length > 1) {
      final Uint8List dropped = _ring.removeAt(0);
      _ringBytesTotal -= dropped.length;
    }
  }

  /// 环形缓冲覆盖的音频时长（毫秒）。
  int ringDurationMs() {
    final int sampleRate = cfg.realtimeSampleRate;
    if (sampleRate <= 0) return 0;
    return (_ringBytesTotal / 2 / sampleRate * 1000).round();
  }

  /// 推入一帧 PCM（**同步方法**，20ms/640B）。
  void pushFrame(Uint8List pcm) {
    if (_closed || _suspended || pcm.isEmpty) return;
    meetingClockMs += 20;
    _appendRing(pcm);
    _pending.addAll(pcm);
    _drain();
  }

  /// 把 `result-generated` 句子映射为 [StreamEvent] 并回调。
  ///
  /// **空句不是进度**（历史 Bug）：此前只要不是「`sentence_begin` + 空文本」，其余空文本
  /// 句也会 `revision++`、打印 `实时句子 ... text=""` 并往逐字稿塞一个空 [StreamEvent] ——
  /// 日志看着像「正在转写」，实际服务端一句语音都没听到；连续空句还会把逐字稿灌成空。
  /// 现在空句被彻底剥离：不计数 revision、不发事件、不打 `实时句子`，只累计告警。
  void _onSentence(Map<String, dynamic> sentence) {
    if (sentence['heartbeat'] == true) return;
    final int sentenceId = _roundNum(sentence['sentence_id']);
    final String text = (sentence['text'] as String?) ?? '';
    if (text.trim().isEmpty) {
      _onEmptySentence(sentenceId, sentence);
      return;
    }

    final int begin = _roundNum(sentence['begin_time']);
    int end = sentence['end_time'] == null ? begin : _roundNum(sentence['end_time']);
    if (sentence['end_time'] == null) {
      final Object? words = sentence['words'];
      if (words is List) {
        for (final Object? word in words) {
          if (word is Map && word['end_time'] != null) {
            final int value = _roundNum(word['end_time']);
            if (value > end) end = value;
          }
        }
      }
    }

    final int revision = (_revById[sentenceId] ?? 0) + 1;
    _revById[sentenceId] = revision;

    logInfo(
      'asr',
      '实时句子 id=$sentenceId final=${sentence['sentence_end'] == true} '
      'begin=${taskBaseMs + begin} end=${taskBaseMs + (end > begin ? end : begin)} '
      'rev=$revision text="${_shorten(text)}"',
    );

    onEvent(
      StreamEvent(
        segmentId: 'seg_$sentenceId',
        speakerId: kPendingSpeakerId,
        text: text,
        startTime: taskBaseMs + begin,
        endTime: taskBaseMs + (end > begin ? end : begin),
        isFinal: sentence['sentence_end'] == true,
        confidence: kFiletransConfidence,
        revision: revision,
      ),
    );
  }

  /// 空句（服务端认为没有有效语音）：只累计 + 节流告警，**绝不伪装成转写进度**。
  void _onEmptySentence(int sentenceId, Map<String, dynamic> sentence) {
    _emptySentenceCount += 1;
    final int now = _now();
    final bool firstEver = _lastEmptyWarnCount == 0 && _lastEmptyWarnAtMs == 0;
    final bool reachBatch =
        _emptySentenceCount - _lastEmptyWarnCount >= kAsrEmptySentenceWarnBatch;
    final bool reachWindow =
        !firstEver &&
        _lastEmptyWarnAtMs > 0 &&
        now - _lastEmptyWarnAtMs >= kAsrEmptySentenceWarnInterval.inMilliseconds;
    if (firstEver || reachBatch || reachWindow) {
      _lastEmptyWarnAtMs = now;
      _lastEmptyWarnCount = _emptySentenceCount;
      logWarn(
        'asr',
        '服务端仅返回空句 ×$_emptySentenceCount（未见有效语音：通常意味着采集到的音频'
        '是静音/无有效信号）session=$sessionId id=$sentenceId',
      );
    }
    if (sentence['sentence_end'] == true) {
      logWarn('asr', '句终但文本为空 id=$sentenceId（本次未识别到语音）session=$sessionId');
    }
  }

  /// 复位空句读数与节流状态（每次开新任务时调用，避免跨任务累计）。
  void _resetEmptySentenceStats() {
    _emptySentenceCount = 0;
    _lastEmptyWarnAtMs = 0;
    _lastEmptyWarnCount = 0;
  }

  /// 任务异常中断：尽力重开（新 `run-task` + 回放环形缓冲 + 时间戳补偿）。
  Future<void> _onTaskDown(String code, String message) async {
    if (_closed || _finishing) return;
    if (_restartCount >= maxRestart) {
      logWarn(
        'asr',
        '实时任务已失败且重试耗尽（$_restartCount/$maxRestart），转由会后终稿兜底',
        <String, Object?>{'code': code, 'message': message, 'session': sessionId},
      );
      onError('实时转写暂不可用（$code）：$message，请依赖会后终稿');
      return;
    }
    _restartCount += 1;
    _restarted = true;
    // 新任务 → 空句读数归零（后续 open() 也会再归一刀，这里提前复位便于诊断观测）。
    _resetEmptySentenceStats();
    // 重启后会把环形缓冲重放给新任务，新任务的内部时间 0 对应「重放起点」，
    // 故时间基准 = 当前时钟 − 环形缓冲时长（避免时间戳整体后移一个环形缓冲时长）。
    final int compensated = meetingClockMs - ringDurationMs();
    taskBaseMs = compensated > 0 ? compensated : 0;
    _task = null;
    logWarn(
      'asr',
      '实时任务中断，重开($_restartCount/$maxRestart)',
      <String, Object?>{
        'code': code,
        'message': message,
        'session': sessionId,
        '回放可覆盖ms': ringDurationMs(),
      },
    );
    try {
      await open();
    } catch (error) {
      onError(error);
    }
  }

  /// 主动收尾：发送残余字节 + `finish-task`，等待 `task-finished`。
  Future<void> flush() async {
    final RealtimeTask? task = _task;
    if (task == null) {
      logInfo('asr', 'flush：无活动任务，跳过 session=$sessionId');
      return;
    }
    _finishing = true;
    _startTimer?.cancel();
    _startTimer = null;
    logInfo(
      'asr',
      'flush 开始 session=$sessionId 残余=${_pending.length}B state=${task.state.name}',
    );
    _drain();
    if (_pending.isNotEmpty && task.state == RealtimeState.running) {
      task.sendAudio(Uint8List.fromList(_pending));
      _pending.clear();
    }
    task.finish();
    await task.finished.timeout(
      const Duration(seconds: 5),
      onTimeout: () => logWarn('asr', '等待 task-finished 超时 session=$sessionId'),
    );
    logInfo('asr', 'flush 完成 session=$sessionId');
  }

  /// 暂停挂起：发残余 + `finish-task` 优雅结束服务端任务并断开连接。
  ///
  /// 为什么必须在暂停时断开：百炼实时任务 **23 秒收不到数据即报
  /// `request timeout after 23 seconds` 并判死任务**——暂停期间不采集、
  /// 不发数据，必然触发。挂起后服务端任务已结束，连接断开，无超时风险。
  ///
  /// 会话对象保留（订阅不变），恢复时 [resume] 重开新任务继续转写。
  /// 挂起时清空环形回放与待发缓冲：服务端已收到暂停前的全部音频，
  /// 恢复后回放旧音频会造成重复转写。
  Future<void> suspend() async {
    if (_suspended || _closed) return;
    _suspended = true;
    _startTimer?.cancel();
    _startTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    final RealtimeTask? task = _task;
    if (task != null) {
      _drain();
      if (_pending.isNotEmpty && task.state == RealtimeState.running) {
        task.sendAudio(Uint8List.fromList(_pending));
        _pending.clear();
      }
      task.finish();
      try {
        await task.finished.timeout(
          const Duration(seconds: 3),
          onTimeout: () => logWarn('asr', '挂起：等待 task-finished 超时 session=$sessionId'),
        );
      } catch (error) {
        logWarn('asr', '挂起：结束任务异常 session=$sessionId：$error');
      }
      task.abort();
    }
    _task = null;
    // 暂停前音频已全部送达服务端；恢复是新任务，回放只会重复转写。
    _pending.clear();
    _ring.clear();
    _ringBytesTotal = 0;
    logInfo('asr', '已挂起（暂停）：任务已结束、连接已断 session=$sessionId 已发=$sentBytes B');
  }

  /// 从挂起恢复：重开新任务继续转写（事件仍走原事件流，订阅不变）。
  Future<void> resume() async {
    if (!_suspended || _closed) return;
    _suspended = false;
    _lastSilencePendingBytes = -1;
    _lastSilenceWarnAtMs = 0;
    logInfo('asr', '从挂起恢复：重开实时任务 session=$sessionId');
    await open();
  }

  /// 关闭（含清理）。
  void close() {
    _closed = true;
    _startTimer?.cancel();
    _startTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    final RealtimeTask? task = _task;
    _task = null;
    logInfo(
      'asr',
      '关闭实时会话 session=$sessionId（state=${task?.state.name ?? 'none'} '
      '已发帧=$sentFrames 已发=${sentBytes}B 服务端消息=$serverMessageCount '
      '心跳=$heartbeatCount pending未发送=${_pending.length}B）',
    );
    task?.abort();
  }

  /// 数值取整（兼容 int / double / String）。
  static int _roundNum(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
