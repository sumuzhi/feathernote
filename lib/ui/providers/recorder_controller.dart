/// 录音控制器：把麦克风 PCM 接到 [BackendApi]（进程内门面）驱动页面状态。
///
/// 链路：`MicSource.startStream` → 分帧（20ms/640B）→ `BackendApi.pushAudioFrame`
/// → 实时 ASR 事件（`BackendApi.events`）→ 上屏；
/// 停止时 `BackendApi.stopRecording` 负责「收尾 → 写 WAV → 归档 → 触发终稿」。
///
/// **U1 采样率兜底**：`record` 7.x 不回调「实际采样率」，Dart 侧无法自动探测。
/// 因此留一个逃生舱：`--dart-define=MIC_ACTUAL_SAMPLE_RATE_HZ=48000`
/// 声明设备真实采集率，`Resampler` 会在分帧前把 PCM 线性重采样到 16000，
/// WAV 头与 `meetings.sample_rate` 仍写 16000（重采样后的真实值）。
///
/// **U6 内存**：这里只做**逐帧转发**，不缓存整段音频；2 小时录音的内存占用是常数级。
///
/// **「只录到 1 秒」的三重防线**（历史 Bug）：
/// 1. `MicSource` 抽象层把 `record` 插件隔离，起流前的权限 / 编码器支持可校验；
/// 2. `pcmStream` 同时挂 `onError` 与 **`onDone`** —— 流被意外关闭不再静默；
/// 3. **看门狗**：录音中连续 [kMicStallTimeout] 收不到任何 chunk 即视为断流，
///    与 `onDone` 走同一条恢复路径（自动重启一次，仍失败则收尾并提示）。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend_api.dart';
import '../../backend/services/session_store.dart';
import '../../backend/services/transcription_service.dart';
import '../../core/error/app_error.dart';
import '../../core/ids.dart';
import '../../core/log/log.dart';
import '../../core/pcm/audio_frame.dart';
import '../../core/pcm/resampler.dart';
import '../../core/platform/mic_source.dart';
import '../../core/platform/recording_foreground_service.dart';
import '../../domain/meeting.dart';
import '../../domain/recording_mode.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../utils/formatters.dart';
import '../widgets/app_toast.dart';
import 'app_providers.dart';

/// 麦克风来源工厂。
///
/// 生产环境是 [RecordMicSource]；`flutter test` 里覆盖为假实现即可驱动完整录音状态机。
final Provider<MicSource Function()> micSourceFactoryProvider =
    Provider<MicSource Function()>((Ref ref) => RecordMicSource.new);

/// 设备真实采集采样率（U1 逃生舱；默认与请求值一致 = 不做重采样）。
const int kMicActualSampleRateHz = int.fromEnvironment(
  'MIC_ACTUAL_SAMPLE_RATE_HZ',
  defaultValue: 16000,
);

/// 目标采样率（百炼实时 ASR 契约值）。
const int kTargetSampleRateHz = 16000;

/// 停录收尾的最长等待时间。
///
/// 收尾正常是毫秒级（落库 + 归档 + 后台触发终稿）；超过该时长即视为卡住，
/// 让 UI 恢复可交互而不是无限转圈。
const Duration kStopTimeout = Duration(seconds: 10);

/// 麦克风静默判定阈值（秒）：录音中连续这么多个看门狗周期没有收到任何 chunk
/// 即视为断流。用「tick 计数」而不是墙上时钟，保证可被假时钟测试覆盖。
const int kMicStallSeconds = 3;

/// 单次录音内允许的自动重启次数（防抖，避免无限重启打转）。
const int kMaxMicRestarts = 1;

/// 音频诊断采样周期。
const Duration kAudioDiagInterval = Duration(seconds: 1);

/// 录音阶段。
enum RecorderPhase {
  /// 待机。
  idle,

  /// 正在准备（建会议 / 开权限 / 开引擎）。
  starting,

  /// 录音中。
  recording,

  /// 已暂停。
  paused,

  /// 正在收尾（停止 → 归档 → 触发终稿）。
  stopping,
}

/// 录音页面状态。
class RecorderUiState {
  /// 构造状态。
  const RecorderUiState({
    required this.phase,
    required this.meetingId,
    required this.sessionId,
    required this.title,
    required this.mode,
    required this.segments,
    required this.speakers,
    required this.bookmarks,
    required this.reconnecting,
    this.error,
  });

  /// 待机态。
  const RecorderUiState.idle()
    : phase = RecorderPhase.idle,
      meetingId = null,
      sessionId = null,
      title = '',
      mode = RecordingMode.meeting,
      segments = const <TranscriptSegment>[],
      speakers = const <Speaker>[],
      bookmarks = const <int>[],
      reconnecting = false,
      error = null;

  /// 当前阶段。
  final RecorderPhase phase;

  /// 会议 ID（未开始为 null）。
  final String? meetingId;

  /// 会话 ID（未开始为 null）。
  final String? sessionId;

  /// 标题。
  final String title;

  /// 模式。
  final RecordingMode mode;

  /// 实时片段（按 `segmentId` upsert 后的顺序）。
  final List<TranscriptSegment> segments;

  /// 说话人表。
  final List<Speaker> speakers;

  /// 书签（毫秒）。
  final List<int> bookmarks;

  /// 是否处于断线重连中（06 号屏）。
  final bool reconnecting;

  /// 最近一次错误（可读文案）。
  final String? error;

  /// 是否处于「录音态」（含暂停）。
  bool get isActive => phase == RecorderPhase.recording || phase == RecorderPhase.paused;

  /// 复制并替换部分字段。
  RecorderUiState copyWith({
    RecorderPhase? phase,
    String? meetingId,
    String? sessionId,
    String? title,
    RecordingMode? mode,
    List<TranscriptSegment>? segments,
    List<Speaker>? speakers,
    List<int>? bookmarks,
    bool? reconnecting,
    String? error,
    bool clearError = false,
  }) {
    return RecorderUiState(
      phase: phase ?? this.phase,
      meetingId: meetingId ?? this.meetingId,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      mode: mode ?? this.mode,
      segments: segments ?? this.segments,
      speakers: speakers ?? this.speakers,
      bookmarks: bookmarks ?? this.bookmarks,
      reconnecting: reconnecting ?? this.reconnecting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 录音控制器。
class RecorderController extends Notifier<RecorderUiState> {
  MicSource? _mic;
  // ignore: cancel_subscriptions  （两个订阅都在 _releaseHardware 中统一取消）
  StreamSubscription<Uint8List>? _pcmSubscription;
  // ignore: cancel_subscriptions
  StreamSubscription<TranscriptEvent>? _eventSubscription;
  Resampler? _resampler;
  final _FrameSlicer _slicer = _FrameSlicer();
  BackendApi? _api;
  Timer? _ticker;
  Timer? _watchdog;
  Timer? _diagTimer;
  int _resumedAtMs = 0;
  int _elapsedBaseMs = 0;
  int _lastWavePushMs = 0;
  bool _disposed = false;

  // ── 诊断 / 恢复计数（「只录到 1 秒」的取证埋点）──
  int _chunkCount = 0;
  int _frameCount = 0;
  int _lastChunkAtMs = 0;
  int _restarts = 0;
  int _stallTicks = 0;
  int _lastWatchdogChunkCount = 0;
  bool _loggedFirstChunk = false;
  bool _loggedFirstFrame = false;
  bool _recovering = false;

  /// 本会话收到的 PCM chunk 数（诊断 / 测试用）。
  int get chunkCount => _chunkCount;

  /// 本会话切出的音频帧数（诊断 / 测试用）。
  int get frameCount => _frameCount;

  /// 本会话触发的麦克风自动重启次数（诊断 / 测试用）。
  int get restartCount => _restarts;

  /// 本会话已上送的 PCM 字节数（= 帧数 × 640B）。
  int get pushedBytes => _frameCount * frameBytes;

  /// 后端活动会话实际落盘的 PCM 字节数（诊断用；无后端返回 -1）。
  int get backendPcmBytes => _api?.activePcmBytes ?? -1;

  @override
  RecorderUiState build() {
    ref.onDispose(() {
      _disposed = true;
      _stopTicker();
      _stopWatchdog();
      _stopDiagnostics();
      unawaited(_releaseHardware());
      unawaited(RecordingForegroundService.instance.stop());
    });
    return const RecorderUiState.idle();
  }

  /// 切换录音模式（待机态分段控件 / 录音态设置弹层）。
  void setMode(RecordingMode mode) {
    if (state.mode == mode) return;
    _emit(state.copyWith(mode: mode));
  }

  /// 已录时长（毫秒，暂停期间不增长）。
  int get elapsedMs {
    if (state.phase != RecorderPhase.recording || _resumedAtMs == 0) {
      return _elapsedBaseMs;
    }
    return _elapsedBaseMs + (DateTime.now().millisecondsSinceEpoch - _resumedAtMs);
  }

  /// 开始录音。
  ///
  /// [title] 为空时按模式自动命名（`会议 09-24 15:28`）。
  Future<void> startRecording({String title = '', RecordingMode? mode}) async {
    if (state.phase != RecorderPhase.idle) return;
    final RecordingMode resolvedMode = mode ?? state.mode;
    _emit(
      state.copyWith(
        phase: RecorderPhase.starting,
        mode: resolvedMode,
        clearError: true,
      ),
    );
    try {
      final BackendApi api = await ref.read(backendProvider.future);
      if (_disposed) return;
      _api = api;

      final String resolvedTitle = title.trim().isNotEmpty
          ? title.trim()
          : '${resolvedMode.titlePrefix} ${formatMonthDayTime(DateTime.now())}';
      final Meeting meeting = await api.createMeeting(
        title: resolvedTitle,
        sampleRate: kTargetSampleRateHz,
      );
      if (_disposed) return;

      final String sessionId = genSessionId();
      // 两个订阅都在 [_releaseHardware] 中统一 cancel（此处无法就地取消）。
      _eventSubscription = api.events.listen(
        _onTranscriptEvent,
        onError: (Object error) => logWarn('recorder', '事件流错误：$error'),
      );
      await api.startRecording(
        meetingId: meeting.id,
        sessionId: sessionId,
        title: resolvedTitle,
      );
      if (_disposed) return;

      final MicSource mic = ref.read(micSourceFactoryProvider)();
      _mic = mic;

      // 1) 权限：`record` 的 hasPermission() 默认会主动申请（request: true）。
      final bool granted = await mic.hasPermission();
      logInfo('recorder', '麦克风权限 granted=$granted');
      if (!granted) {
        throw const AppError(ErrorCode.badRequest, '未获得麦克风权限，请在系统设置中开启后重试');
      }

      // 2) 设备能力：不支持 PCM16 流式采集时给出可读错误，而不是静默无数据。
      final bool pcmOk = await mic.isPcmSupported();
      logInfo('recorder', 'PCM16 采集支持=$pcmOk');
      if (!pcmOk) {
        throw const AppError(ErrorCode.badRequest, '当前设备不支持 PCM16 流式采集，无法录音');
      }

      // 3) 前台服务（Android）：Android 14+ 未起 microphone 型前台服务时，
      //    麦克风流可能被系统提前掐断（「只录一小会儿」的典型诱因）。
      await RecordingForegroundService.instance.start();

      // 4) 起流。
      final Stream<Uint8List> pcmStream = await mic.startStream(
        sampleRateHz: kTargetSampleRateHz,
        channels: 1,
      );
      _resampler = kMicActualSampleRateHz == kTargetSampleRateHz
          ? null
          : Resampler(fromHz: kMicActualSampleRateHz, toHz: kTargetSampleRateHz);
      _slicer.reset();
      _chunkCount = 0;
      _frameCount = 0;
      _restarts = 0;
      _stallTicks = 0;
      _lastWatchdogChunkCount = 0;
      _loggedFirstChunk = false;
      _loggedFirstFrame = false;
      _recovering = false;
      _lastChunkAtMs = _nowMs();
      _pcmSubscription = _listenPcm(pcmStream);

      _elapsedBaseMs = 0;
      _resumedAtMs = DateTime.now().millisecondsSinceEpoch;
      _lastWavePushMs = 0;
      _startTicker();
      _startWatchdog();
      _startDiagnostics();
      ref.read(waveformProvider.notifier).reset();
      ref.read(recordingClockProvider.notifier).set(0);

      _emit(
        state.copyWith(
          phase: RecorderPhase.recording,
          meetingId: meeting.id,
          sessionId: sessionId,
          title: resolvedTitle,
          segments: const <TranscriptSegment>[],
          speakers: const <Speaker>[],
          bookmarks: const <int>[],
          reconnecting: false,
          clearError: true,
        ),
      );
      logInfo('recorder', '开始录音 meeting=${meeting.id} session=$sessionId');
    } catch (error) {
      await _releaseHardware();
      await RecordingForegroundService.instance.stop();
      _stopTicker();
      _stopWatchdog();
      _stopDiagnostics();
      if (_disposed) return;
      _emit(
        state.copyWith(
          phase: RecorderPhase.idle,
          error: _readable(error),
        ),
      );
      ref.read(toastProvider.notifier).show(
        _readable(error),
        tone: ToastTone.warning,
      );
    }
  }

  /// 暂停 / 继续。
  Future<void> togglePause() async {
    final MicSource? mic = _mic;
    if (mic == null) return;
    if (state.phase == RecorderPhase.recording) {
      _elapsedBaseMs = elapsedMs;
      _resumedAtMs = 0;
      _emit(state.copyWith(phase: RecorderPhase.paused));
      _stopTicker();
      try {
        await mic.pause();
      } catch (error) {
        logWarn('recorder', '暂停失败：$error');
        _failWith('暂停失败：$error');
      }
      return;
    }
    if (state.phase == RecorderPhase.paused) {
      _resumedAtMs = DateTime.now().millisecondsSinceEpoch;
      _emit(state.copyWith(phase: RecorderPhase.recording));
      _startTicker();
      // 重置看门狗基准，避免恢复瞬间被误判为断流。
      _lastChunkAtMs = _nowMs();
      try {
        await mic.resume();
      } catch (error) {
        logWarn('recorder', '继续失败：$error');
        _failWith('继续失败：$error');
      }
    }
  }

  /// 添加书签（当前实现仅内存记录 + 提示，见交付说明）。
  void addBookmark() {
    if (!state.isActive) return;
    final int at = elapsedMs;
    _emit(state.copyWith(bookmarks: <int>[...state.bookmarks, at]));
    ref.read(toastProvider.notifier).show('已添加书签 · ${formatClock(at)}');
  }

  /// 结束录音并返回会议 ID（由页面负责跳转到纪要页）。
  ///
  /// **收尾超时兜底**：`stopRecording` 内部包含「逐字稿落库 + WAV 归档 +
  /// 后台触发终稿」；正常情况下毫秒级返回。若因 IO / 网络异常卡住，
  /// 这里最多等 [kStopTimeout]，超时不再卡在 `stopping`，而是回到待机并提示
  /// 「已在后台继续处理」，用户可在历史页查看终稿状态。
  Future<String?> stopAndGenerate() async {
    final String? meetingId = state.meetingId;
    if (meetingId == null) return null;
    _elapsedBaseMs = elapsedMs;
    _resumedAtMs = 0;
    _emit(state.copyWith(phase: RecorderPhase.stopping));
    _stopTicker();
    _stopWatchdog();
    _stopDiagnostics();
    // 收尾前先打一次总账，供「只录到 1 秒」类问题定位。
    logInfo(
      'recorder',
      '收尾总账 meeting=$meetingId 已录=${_elapsedBaseMs}ms chunk=$_chunkCount '
      '帧=$_frameCount 上送=${pushedBytes}B 后端落盘=${backendPcmBytes}B 重启=$_restarts',
    );
    await _releaseHardware();
    final BackendApi? api = _api;
    if (api != null) {
      try {
        await api.stopRecording(meetingId).timeout(kStopTimeout);
        logInfo(
          'recorder',
          '录音已停止 meeting=$meetingId 后端落盘=${api.activePcmBytes}B',
        );
      } on TimeoutException {
        logWarn('recorder', '收尾超时（${kStopTimeout.inSeconds}s），已转后台 meeting=$meetingId');
        ref.read(toastProvider.notifier).show(
          '收尾超时，已在后台继续处理，可在历史页查看终稿状态',
          tone: ToastTone.warning,
        );
      } catch (error) {
        logWarn('recorder', '停止流程报错：$error');
        ref.read(toastProvider.notifier).show(
          '收尾失败，转写可能不完整：${_readable(error)}',
          tone: ToastTone.warning,
        );
      }
    }
    await RecordingForegroundService.instance.stop();
    if (_disposed) return meetingId;
    _emit(const RecorderUiState.idle());
    ref.read(waveformProvider.notifier).reset();
    ref.read(recordingClockProvider.notifier).reset();
    return meetingId;
  }

  /// 放弃本次录音（✕）。
  Future<void> discard() async {
    final String? meetingId = state.meetingId;
    _stopTicker();
    _stopWatchdog();
    _stopDiagnostics();
    await _releaseHardware();
    if (meetingId != null) {
      try {
        await _api?.stopRecording(meetingId);
        await _api?.deleteMeeting(meetingId);
      } catch (error) {
        logWarn('recorder', '丢弃录音失败：$error');
      }
    }
    await RecordingForegroundService.instance.stop();
    if (_disposed) return;
    _emit(const RecorderUiState.idle());
    ref.read(waveformProvider.notifier).reset();
    ref.read(recordingClockProvider.notifier).reset();
  }

  // ── 内部实现 ──

  StreamSubscription<Uint8List> _listenPcm(Stream<Uint8List> stream) {
    return stream.listen(
      _onPcmChunk,
      onError: (Object error) {
        logWarn('recorder', '麦克风流错误：$error');
        _failWith('录音中断：$error');
        unawaited(_recoverMic('流错误：$error'));
      },
      // 历史 Bug：只处理了 onError，流被意外关闭（onDone）时毫无反馈，
      // 于是 UI 一直显示「录音中」但音频早已停止。
      onDone: () {
        logWarn('recorder', '麦克风流已结束（onDone）：chunk=$_chunkCount 帧=$_frameCount');
        unawaited(_recoverMic('输入流被系统关闭'));
      },
      cancelOnError: false,
    );
  }

  void _onPcmChunk(Uint8List chunk) {
    _lastChunkAtMs = _nowMs();
    _chunkCount++;
    if (!_loggedFirstChunk) {
      _loggedFirstChunk = true;
      logInfo('recorder', '首个 PCM chunk=${chunk.length}B（开始收到音频）');
    }
    final Resampler? resampler = _resampler;
    final Uint8List pcm = resampler == null ? chunk : resampler.convert(chunk);
    if (pcm.isEmpty) return;
    final List<AudioFrame> frames = _slicer.push(pcm);
    for (final AudioFrame frame in frames) {
      _frameCount++;
      if (!_loggedFirstFrame) {
        _loggedFirstFrame = true;
        logInfo('recorder', '首个音频帧 seq=${frame.seq} startMs=${frame.startMs} ${frame.pcm.length}B');
      }
      _api?.pushAudioFrame(frame);
      _pushWaveLevel(frame.pcm);
    }
  }

  /// 麦克风异常中断的统一恢复路径：先试着重启一次，仍不行就收尾并提示。
  Future<void> _recoverMic(String reason) async {
    if (_disposed) return;
    if (state.phase != RecorderPhase.recording && state.phase != RecorderPhase.paused) {
      return;
    }
    if (_recovering) return;
    _recovering = true;
    try {
      if (_restarts >= kMaxMicRestarts) {
        logWarn('recorder', '麦克风中断（$reason）且已达重启上限 $_restarts，转入收尾');
        await _abortAfterMicFailure(reason);
        return;
      }
      _restarts++;
      logWarn('recorder', '麦克风中断（$reason），尝试第 $_restarts 次自动重启');
      ref.read(toastProvider.notifier).show(
        '录音中断（$reason），正在自动恢复…',
        tone: ToastTone.warning,
      );
      final MicSource? mic = _mic;
      if (mic == null) {
        await _abortAfterMicFailure(reason);
        return;
      }
      final Stream<Uint8List> pcm = await mic.startStream(
        sampleRateHz: kTargetSampleRateHz,
        channels: 1,
      );
      if (_disposed) return;
      await _pcmSubscription?.cancel();
      _lastChunkAtMs = _nowMs();
      _pcmSubscription = _listenPcm(pcm);
      logInfo('recorder', '麦克风已自动恢复（第 $_restarts 次）');
    } catch (error) {
      logWarn('recorder', '麦克风自动恢复失败：$error');
      await _abortAfterMicFailure('$reason / 恢复失败：${_readable(error)}');
    } finally {
      _recovering = false;
    }
  }

  /// 不可恢复的麦克风中断：收尾当前会议（保留已录内容）并回到待机。
  Future<void> _abortAfterMicFailure(String reason) async {
    final String? meetingId = state.meetingId;
    _stopTicker();
    _stopWatchdog();
    _stopDiagnostics();
    await _releaseHardware();
    if (meetingId != null) {
      try {
        await _api?.stopRecording(meetingId).timeout(kStopTimeout);
      } catch (error) {
        logWarn('recorder', '中断后的收尾失败：$error');
      }
    }
    await RecordingForegroundService.instance.stop();
    if (_disposed) return;
    _emit(const RecorderUiState.idle());
    ref.read(waveformProvider.notifier).reset();
    ref.read(recordingClockProvider.notifier).reset();
    ref.read(toastProvider.notifier).show(
      '录音已中断并自动收尾（$reason），本次内容已保留，可在历史页查看',
      tone: ToastTone.warning,
      duration: const Duration(seconds: 5),
    );
  }

  void _pushWaveLevel(Uint8List pcm) {
    final int now = _nowMs();
    if (now - _lastWavePushMs < 60) return;
    _lastWavePushMs = now;
    ref.read(waveformProvider.notifier).push(_levelOf(pcm));
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (Timer _) {
      if (_disposed) return;
      ref.read(recordingClockProvider.notifier).set(elapsedMs);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 看门狗：录音中长时间收不到 chunk（流被静默掐断）也能被发现。
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (_disposed) return;
      // 暂停 / 恢复中本来就不产数据，不做静默判定。
      if (state.phase != RecorderPhase.recording || _recovering) {
        _lastWatchdogChunkCount = _chunkCount;
        _stallTicks = 0;
        return;
      }
      if (_chunkCount != _lastWatchdogChunkCount) {
        _lastWatchdogChunkCount = _chunkCount;
        _stallTicks = 0;
        return;
      }
      _stallTicks++;
      if (_stallTicks < kMicStallSeconds) return;
      _stallTicks = 0;
      _lastWatchdogChunkCount = _chunkCount;
      unawaited(_recoverMic('连续 $kMicStallSeconds 秒未收到音频数据'));
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// 每秒输出一次音频诊断（「只录到 1 秒」类问题的现场记录）。
  void _startDiagnostics() {
    _diagTimer?.cancel();
    _diagTimer = Timer.periodic(kAudioDiagInterval, (Timer _) {
      if (_disposed) return;
      logInfo(
        'recorder',
        '音频诊断 已录=${elapsedMs}ms chunk=$_chunkCount 帧=$_frameCount '
        '上送=${pushedBytes}B 后端落盘=${backendPcmBytes}B '
        '距上次chunk=${_nowMs() - _lastChunkAtMs}ms 阶段=${state.phase.name} 重启=$_restarts',
      );
    });
  }

  void _stopDiagnostics() {
    _diagTimer?.cancel();
    _diagTimer = null;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  void _onTranscriptEvent(TranscriptEvent transcriptEvent) {
    if (_disposed) return;
    final String? meetingId = state.meetingId;
    switch (transcriptEvent) {
      case TranscriptUpsert(:final StreamEvent event):
        if (transcriptEvent.meetingId != meetingId) return;
        _upsertSegment(event);
      case TranscriptReplace(:final List<TranscriptSegment> segments, :final List<Speaker> speakers):
        if (transcriptEvent.meetingId != meetingId) return;
        _emit(
          state.copyWith(
            segments: segments,
            speakers: speakers,
            reconnecting: false,
          ),
        );
      case SpeakerUpdate(:final List<Speaker> speakers):
        if (transcriptEvent.meetingId != meetingId) return;
        _emit(state.copyWith(speakers: speakers));
      case EngineErrorEvent(:final String message):
        _emit(state.copyWith(reconnecting: true));
        ref.read(toastProvider.notifier).show(
          message.isEmpty ? '网络波动，正在自动重连…' : message,
          tone: ToastTone.warning,
          sticky: true,
        );
      case MeetingStopped():
        break;
      case MeetingStarted():
        break;
      case FinalizeProgress():
        break;
    }
  }

  void _upsertSegment(StreamEvent event) {
    final List<TranscriptSegment> next = <TranscriptSegment>[...state.segments];
    final int index = next.indexWhere((TranscriptSegment s) => s.segmentId == event.segmentId);
    final TranscriptSegment segment = TranscriptSegment(
      meetingId: state.meetingId ?? '',
      segmentId: event.segmentId,
      ordinal: index >= 0 ? next[index].ordinal : next.length,
      speakerId: event.speakerId,
      speakerName: event.speakerName,
      text: event.text,
      startTime: event.startTime,
      endTime: event.endTime,
      confidence: event.confidence,
      seqStart: event.startTime ~/ kSessionFrameMs,
      seqEnd: (event.endTime / kSessionFrameMs).ceil() - 1,
    );
    if (index >= 0) {
      next[index] = segment;
    } else {
      next.add(segment);
    }
    _emit(state.copyWith(segments: next, reconnecting: false));
    if (state.reconnecting) {
      ref.read(toastProvider.notifier).clear();
    }
  }

  void _failWith(String message) {
    if (_disposed) return;
    ref.read(toastProvider.notifier).show(message, tone: ToastTone.warning);
  }

  Future<void> _releaseHardware() async {
    final StreamSubscription<Uint8List>? pcm = _pcmSubscription;
    _pcmSubscription = null;
    await pcm?.cancel();
    final StreamSubscription<TranscriptEvent>? events = _eventSubscription;
    _eventSubscription = null;
    await events?.cancel();
    final MicSource? mic = _mic;
    _mic = null;
    if (mic != null) {
      try {
        await mic.stop();
      } catch (error) {
        logWarn('recorder', '停止麦克风失败：$error');
      }
      try {
        await mic.dispose();
      } catch (error) {
        logWarn('recorder', '释放麦克风失败：$error');
      }
    }
  }

  void _emit(RecorderUiState next) {
    if (_disposed) return;
    state = next;
  }

  String _readable(Object error) {
    if (error is AppError) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

/// 把不定长 PCM 流切成 20ms / 640B 的帧（`AudioFrame` 契约）。
class _FrameSlicer {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _seq = 0;

  /// 复位（重新开始录音时调用）。
  void reset() {
    _buffer.clear();
    _seq = 0;
  }

  /// 追加一段 PCM，返回本次可产出的完整帧。
  List<AudioFrame> push(Uint8List chunk) {
    if (chunk.isEmpty) return const <AudioFrame>[];
    _buffer.add(chunk);
    final List<AudioFrame> frames = <AudioFrame>[];
    while (_buffer.length >= frameBytes) {
      final Uint8List all = _buffer.takeBytes();
      int offset = 0;
      while (all.length - offset >= frameBytes) {
        final Uint8List pcm = Uint8List.fromList(
          Uint8List.sublistView(all, offset, offset + frameBytes),
        );
        frames.add(
          AudioFrame(flag: 0, seq: _seq, startMs: _seq * kSessionFrameMs, pcm: pcm),
        );
        offset += frameBytes;
        _seq++;
      }
      if (offset < all.length) {
        _buffer.add(Uint8List.sublistView(all, offset));
      }
    }
    return frames;
  }
}

/// 由 PCM16LE 计算归一化音量（0–1），用于波形柱高。
double _levelOf(Uint8List pcm) {
  if (pcm.length < 4) return 0;
  final ByteData view = ByteData.view(pcm.buffer, pcm.offsetInBytes, pcm.length);
  int sum = 0;
  int count = 0;
  for (int i = 0; i + 1 < pcm.length; i += 2) {
    final int sample = view.getInt16(i, Endian.little);
    sum += sample * sample;
    count++;
  }
  if (count == 0) return 0;
  final double rms = math.sqrt(sum / count);
  final double normalized = (rms / 5000).clamp(0.0, 1.0);
  // 0.6 次幂：提升小音量在视觉上的可见性。
  return math.pow(normalized, 0.6).toDouble();
}

/// 录音控制器 provider。
final NotifierProvider<RecorderController, RecorderUiState> recorderProvider =
    NotifierProvider<RecorderController, RecorderUiState>(RecorderController.new);
