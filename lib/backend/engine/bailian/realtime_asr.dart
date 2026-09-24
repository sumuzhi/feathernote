/// 百炼实时流式 ASR（`RealtimeTask` 状态机 + `BailianRealtimeSession` 聚合）。
///
/// 移植 `dashscopeClient.js:450-682` 与 `realAdapters.js:99-411`。
/// 关键约束（复刻时不可走样）：
/// 1. 鉴权在**握手 HTTP 头**（`Authorization: Bearer <key>`）—— `dart:io` 的
///    `WebSocket.connect(url, headers: ...)` 原生支持，这是方案 B 相对 WebView 的决定性优势；
/// 2. 收到 `task-started` 后才可发音频；
/// 3. `task-failed` 会关连接且不可复用 → 重连必须**重开 run-task**（新 taskId，旧上下文作废）；
/// 4. `result-generated` 的 heartbeat 句要过滤；
/// 5. 向百炼下发按 **100ms / 3200B 聚合**（不是逐 640B 帧）。
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
      logInfo('asr', '正在连接实时服务 task=$taskId url=$url');
      _socket = await _socketFactory(url, headers);
    } catch (error) {
      state = RealtimeState.failed;
      // 连接阶段失败（DNS / TLS / 401 鉴权 / 域名错误）必须带上 URL 与原因，
      // 否则「音频在收音却没有转写」将无从定位。
      logWarn(
        'asr',
        '实时连接失败 task=$taskId url=$url 原因=${error.runtimeType}: $error',
      );
      handlers.onError?.call(RealtimeFailure('连接失败（$url）：$error'));
      _resolve();
      return;
    }
    _subscription = _socket!.messages.listen(
      _onMessage,
      onError: (Object error) => handlers.onError?.call(error),
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
    switch (event) {
      case 'task-started':
        state = RealtimeState.running;
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

  /// 连接关闭。
  void _onClose() {
    if (state != RealtimeState.finished && state != RealtimeState.failed) {
      state = RealtimeState.closed;
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
  }) : chunkBytes = ((cfg.realtimeFrameMs / 1000) * cfg.realtimeSampleRate).round() * 2,
       ringBytes = ((cfg.realtimeRingMs / 1000) * cfg.realtimeSampleRate).round() * 2;

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
  bool _closed = false;
  bool _finishing = false;
  bool _restarted = false;
  int _restartCount = 0;

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
    final RealtimeTask task = RealtimeTask(
      cfg,
      handlers: RealtimeHandlers(
        onStarted: _onStarted,
        onSentence: (Map<String, dynamic> sentence, Map<String, dynamic> payload) =>
            _onSentence(sentence),
        onFinished: () => logInfo('asr', '实时任务已结束 session=$sessionId'),
        onFailed: (String code, String message) => unawaited(_onTaskDown(code, message)),
        onError: onError,
      ),
      socketFactory: socketFactory,
    );
    _task = task;
    // 启动看门狗：握手后若迟迟不 `task-started`（服务端静默 / 连接被静默关闭），
    // 到点即判失败并上报，避免音频帧无声无息地堆在 `_pending` 里。
    _startTimer?.cancel();
    _startTimer = Timer(startTimeout, _onStartTimeout);
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
    }
    _restarted = false;
    _drain();
    logInfo('asr', '实时任务已就绪 session=$sessionId meeting=$meetingId');
  }

  /// 把累积的 PCM 凑满 [chunkBytes] 后下发。
  void _drain() {
    final RealtimeTask? task = _task;
    if (task == null || task.state != RealtimeState.running) return;
    while (_pending.length >= chunkBytes) {
      final Uint8List chunk = Uint8List.fromList(_pending.sublist(0, chunkBytes));
      _pending.removeRange(0, chunkBytes);
      task.sendAudio(chunk);
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
    if (_closed || pcm.isEmpty) return;
    meetingClockMs += 20;
    _appendRing(pcm);
    _pending.addAll(pcm);
    _drain();
  }

  /// 把 `result-generated` 句子映射为 [StreamEvent] 并回调。
  void _onSentence(Map<String, dynamic> sentence) {
    if (sentence['heartbeat'] == true) return;
    final int sentenceId = _roundNum(sentence['sentence_id']);
    final String text = (sentence['text'] as String?) ?? '';
    // 句子开始事件（空文本）：仅建立 revision 基线，不上屏。
    if (sentence['sentence_begin'] == true && text.isEmpty) {
      _revById.putIfAbsent(sentenceId, () => 0);
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

  /// 任务异常中断：尽力重开（新 `run-task` + 回放环形缓冲 + 时间戳补偿）。
  Future<void> _onTaskDown(String code, String message) async {
    if (_closed || _finishing) return;
    if (_restartCount >= maxRestart) {
      onError('实时转写暂不可用（$code）：$message，请依赖会后终稿');
      return;
    }
    _restartCount += 1;
    _restarted = true;
    // 重启后会把环形缓冲重放给新任务，新任务的内部时间 0 对应「重放起点」，
    // 故时间基准 = 当前时钟 − 环形缓冲时长（避免时间戳整体后移一个环形缓冲时长）。
    final int compensated = meetingClockMs - ringDurationMs();
    taskBaseMs = compensated > 0 ? compensated : 0;
    _task = null;
    logWarn(
      'asr',
      '实时任务中断，重开($_restartCount/$maxRestart)',
      <String, Object?>{'code': code, 'session': sessionId},
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
    if (task == null) return;
    _finishing = true;
    _startTimer?.cancel();
    _startTimer = null;
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
  }

  /// 关闭（含清理）。
  void close() {
    _closed = true;
    _startTimer?.cancel();
    _startTimer = null;
    final RealtimeTask? task = _task;
    _task = null;
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
