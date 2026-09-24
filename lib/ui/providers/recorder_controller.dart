/// 录音控制器：把麦克风 PCM 接到 [BackendApi]（进程内门面）驱动页面状态。
///
/// 链路：`AudioRecorder.startStream` → 分帧（20ms/640B）→ `BackendApi.pushAudioFrame`
/// → 实时 ASR 事件（`BackendApi.events`）→ 上屏；
/// 停止时 `BackendApi.stopRecording` 负责「收尾 → 写 WAV → 归档 → 触发终稿」。
///
/// **U1 采样率兜底**：`record` 7.x 不回调「实际采样率」，Dart 侧无法自动探测。
/// 因此留一个逃生舱：`--dart-define=MIC_ACTUAL_SAMPLE_RATE_HZ=48000`
/// 声明设备真实采集率，`Resampler` 会在分帧前把 PCM 线性重采样到 16000，
/// WAV 头与 `meetings.sample_rate` 仍写 16000（重采样后的真实值）。
///
/// **U6 内存**：这里只做**逐帧转发**，不缓存整段音频；2 小时录音的内存占用是常数级。
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../backend/backend_api.dart';
import '../../backend/services/session_store.dart';
import '../../backend/services/transcription_service.dart';
import '../../core/error/app_error.dart';
import '../../core/ids.dart';
import '../../core/log/log.dart';
import '../../core/pcm/audio_frame.dart';
import '../../core/pcm/resampler.dart';
import '../../domain/meeting.dart';
import '../../domain/recording_mode.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../utils/formatters.dart';
import '../widgets/app_toast.dart';
import 'app_providers.dart';

/// 设备真实采集采样率（U1 逃生舱；默认与请求值一致 = 不做重采样）。
const int kMicActualSampleRateHz = int.fromEnvironment(
  'MIC_ACTUAL_SAMPLE_RATE_HZ',
  defaultValue: 16000,
);

/// 目标采样率（百炼实时 ASR 契约值）。
const int kTargetSampleRateHz = 16000;

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
  AudioRecorder? _recorder;
  // ignore: cancel_subscriptions  （两个订阅都在 _releaseHardware 中统一取消）
  StreamSubscription<Uint8List>? _pcmSubscription;
  // ignore: cancel_subscriptions
  StreamSubscription<TranscriptEvent>? _eventSubscription;
  Resampler? _resampler;
  final _FrameSlicer _slicer = _FrameSlicer();
  BackendApi? _api;
  Timer? _ticker;
  int _resumedAtMs = 0;
  int _elapsedBaseMs = 0;
  int _lastWavePushMs = 0;
  bool _disposed = false;

  @override
  RecorderUiState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_releaseHardware());
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

      final AudioRecorder recorder = AudioRecorder();
      _recorder = recorder;
      final bool granted = await recorder.hasPermission();
      if (!granted) {
        throw const AppError(ErrorCode.badRequest, '未获得麦克风权限，请在系统设置中开启后重试');
      }
      final Stream<Uint8List> pcmStream = await recorder.startStream(_recordConfig());
      _resampler = kMicActualSampleRateHz == kTargetSampleRateHz
          ? null
          : Resampler(fromHz: kMicActualSampleRateHz, toHz: kTargetSampleRateHz);
      _slicer.reset();
      _pcmSubscription = pcmStream.listen(
        _onPcmChunk,
        onError: (Object error) => _failWith('录音中断：$error'),
        cancelOnError: false,
      );

      _elapsedBaseMs = 0;
      _resumedAtMs = DateTime.now().millisecondsSinceEpoch;
      _lastWavePushMs = 0;
      _startTicker();
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
      _stopTicker();
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
    final AudioRecorder? recorder = _recorder;
    if (recorder == null) return;
    if (state.phase == RecorderPhase.recording) {
      _elapsedBaseMs = elapsedMs;
      _resumedAtMs = 0;
      _emit(state.copyWith(phase: RecorderPhase.paused));
      _stopTicker();
      try {
        await recorder.pause();
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
      try {
        await recorder.resume();
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
  Future<String?> stopAndGenerate() async {
    final String? meetingId = state.meetingId;
    if (meetingId == null) return null;
    _elapsedBaseMs = elapsedMs;
    _resumedAtMs = 0;
    _emit(state.copyWith(phase: RecorderPhase.stopping));
    _stopTicker();
    await _releaseHardware();
    try {
      await _api?.stopRecording(meetingId);
      logInfo('recorder', '录音已停止 meeting=$meetingId');
    } catch (error) {
      logWarn('recorder', '停止流程报错：$error');
      ref.read(toastProvider.notifier).show(
        '收尾失败，转写可能不完整：${_readable(error)}',
        tone: ToastTone.warning,
      );
    }
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
    await _releaseHardware();
    if (meetingId != null) {
      try {
        await _api?.stopRecording(meetingId);
        await _api?.deleteMeeting(meetingId);
      } catch (error) {
        logWarn('recorder', '丢弃录音失败：$error');
      }
    }
    if (_disposed) return;
    _emit(const RecorderUiState.idle());
    ref.read(waveformProvider.notifier).reset();
    ref.read(recordingClockProvider.notifier).reset();
  }

  // ── 内部实现 ──

  RecordConfig _recordConfig() => const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: kTargetSampleRateHz,
    numChannels: 1,
    // U3：固定新实现（advanced recorder），legacy 仅供极端兼容场景。
    androidConfig: AndroidRecordConfig(useLegacy: false),
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  void _onPcmChunk(Uint8List chunk) {
    final Resampler? resampler = _resampler;
    final Uint8List pcm = resampler == null ? chunk : resampler.convert(chunk);
    if (pcm.isEmpty) return;
    final List<AudioFrame> frames = _slicer.push(pcm);
    for (final AudioFrame frame in frames) {
      _api?.pushAudioFrame(frame);
      _pushWaveLevel(frame.pcm);
    }
  }

  void _pushWaveLevel(Uint8List pcm) {
    final int now = DateTime.now().millisecondsSinceEpoch;
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
    final AudioRecorder? recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (error) {
        logWarn('recorder', '停止麦克风失败：$error');
      }
      try {
        await recorder.dispose();
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
  // 0.6 次幂：提升小音量在视觉上的可见度。
  return math.pow(normalized, 0.6).toDouble();
}

/// 录音控制器 provider。
final NotifierProvider<RecorderController, RecorderUiState> recorderProvider =
    NotifierProvider<RecorderController, RecorderUiState>(RecorderController.new);
