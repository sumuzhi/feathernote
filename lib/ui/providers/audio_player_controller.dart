/// 转写页音频播放控制器：单例播放器 + 按 segment 互斥播放。
///
/// 设计约束：
/// - 一场会议 = 一个完整 WAV 文件；「播某一段」= seek 到 startMs、播到 endMs 自动停。
/// - 同时只播一段（互斥）。
/// - 播放依赖已存在的 `just_audio`，但代码里必须把它隔离在 [AudioPlayerEngine] 后面，
///   否则 `flutter test` 无法运行（真实播放器在测试环境没有原生实现）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../backend/backend_api.dart';
import '../utils/transcript_timeline.dart';
import '../widgets/app_toast.dart';
import 'app_providers.dart';

/// 播放器抽象：把 `just_audio` 与控制器解耦，测试可注入假实现。
abstract class AudioPlayerEngine {
  /// 加载本地文件，返回音频时长（可能为 null）。
  Future<Duration?> setFilePath(String path);

  /// 播放。
  Future<void> play();

  /// 暂停。
  Future<void> pause();

  /// seek 到指定位置。
  Future<void> seek(Duration position);

  /// 当前播放位置。
  Duration get currentPosition;

  /// 位置流（控制器用它做自动停 + 高亮）。
  Stream<Duration> get positionStream;

  /// 播放器状态流（playing / paused / completed）。
  Stream<PlayerState> get playerStateStream;

  /// 释放资源。
  Future<void> dispose();
}

/// `just_audio` 真实实现。
class JustAudioEngine implements AudioPlayerEngine {
  JustAudioEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<Duration?> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Duration get currentPosition => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Future<void> dispose() => _player.dispose();
}

/// 播放器状态。
class AudioPlayerState {
  /// 构造状态。
  const AudioPlayerState({
    this.playingSegmentId,
    this.playingStartMs = -1,
    this.isPlaying = false,
    this.currentPositionMs = 0,
    this.durationMs = 0,
    this.currentMeetingId,
    this.error,
  });

  /// 当前正在播放（或最后播放）的 segmentId。
  final String? playingSegmentId;

  /// 当前段的起始毫秒（与 [playingSegmentId] 组成复合定位键）。
  ///
  /// 为什么要带上起点：实时 ASR 的 `segmentId` 是 `seg_$sentenceId`，而**任务重启后
  /// sentence 编号会从 1 重新开始**，与旧的 `seg_1` 撞车（`SessionStore` 与数据库都
  /// 以 segmentId 为键）。只按 segmentId 定位"当前段"会命中错误的条目。
  final int playingStartMs;

  /// 段的复合定位键（日志 / 测试用）。
  static String keyOf(String segmentId, int startMs) => '$segmentId@$startMs';

  /// 当前段的复合定位键（无当前段时为 null）。
  String? get playingSegmentKey =>
      playingSegmentId == null ? null : keyOf(playingSegmentId!, playingStartMs);

  /// 是否正在播放。
  final bool isPlaying;

  /// 当前播放位置（毫秒）。
  final int currentPositionMs;

  /// 当前音频总时长（毫秒）。
  final int durationMs;

  /// 当前加载的会议 ID。
  final String? currentMeetingId;

  /// 最近一次错误文案（null 为无错误）。
  final String? error;

  /// 是否当前 segment 正在播放。
  ///
  /// [startMs] 必须一并比对（见 [playingStartMs] 关于 segmentId 撞车的说明）。
  bool isSegmentPlaying(String segmentId, int startMs) =>
      playingSegmentId == segmentId && playingStartMs == startMs && isPlaying;

  /// 该 segment 是否为「当前段」（正在播放**或已暂停停在该段**）。
  ///
  /// 只有当前段才展示进度条与「已播 / 段长」；播完/切走后自动清除，避免出现
  /// 「上一个段的进度组件残留、点其它按钮时位置错位」。
  bool isSegmentActive(String segmentId, int startMs) =>
      playingSegmentId == segmentId && playingStartMs == startMs;

  /// 复制并替换部分字段。
  AudioPlayerState copyWith({
    String? playingSegmentId,
    bool? isPlaying,
    int? currentPositionMs,
    int? durationMs,
    String? currentMeetingId,
    String? error,
    bool clearError = false,
    int? playingStartMs,

    /// 清除「当前段」标记（播完 / 切走时用：`??` 无法把字段置回 null）。
    bool clearActive = false,
  }) =>
      AudioPlayerState(
        playingSegmentId: clearActive
            ? null
            : (playingSegmentId ?? this.playingSegmentId),
        playingStartMs: clearActive ? -1 : (playingStartMs ?? this.playingStartMs),
        isPlaying: isPlaying ?? this.isPlaying,
        currentPositionMs: currentPositionMs ?? this.currentPositionMs,
        durationMs: durationMs ?? this.durationMs,
        currentMeetingId: currentMeetingId ?? this.currentMeetingId,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 音频播放控制器。
class AudioPlayerController extends Notifier<AudioPlayerState> {
  // ignore: prefer_initializing_formals
  AudioPlayerController({AudioPlayerEngine? engine}) : _engine = engine;

  /// 注入的播放器引擎（测试用）。
  final AudioPlayerEngine? _engine;
  AudioPlayerEngine? _resolvedEngine;
  BackendApi? _api;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  /// 当前目标结束时间（毫秒），用于自动停。
  int _endMs = 0;

  /// 「我们是否打算在播」的意图标记。
  ///
  /// 存在的理由（**首次点击不显示播放组件的根因**）：`just_audio` 的
  /// `playerStateStream` 是 `startWith` 流，**订阅瞬间会回放当前值**；
  /// 首次点击时引擎刚创建、订阅刚建立，这个回放事件可能在我们把
  /// `isPlaying=true` 之后才到达，把状态打回 false → 音频在放但组件不显示。
  /// 此后订阅已存在、不再有回放事件，所以只有"第一次"会复现。
  /// 因此：由我们自己调用 `pause()` / 自动停来置 false，忽略与意图相反的迟到事件。
  bool _intentPlaying = false;

  /// 是否已释放（ Riverpod 3 Notifier 没有 `mounted`，自己跟踪）。
  bool _disposed = false;

  @override
  AudioPlayerState build() {
    ref.onDispose(_dispose);
    return const AudioPlayerState();
  }

  AudioPlayerEngine get _player {
    final AudioPlayerEngine? resolved = _resolvedEngine;
    if (resolved != null) return resolved;
    final AudioPlayerEngine engine = _engine ?? JustAudioEngine();
    _resolvedEngine = engine;
    _stateSub = engine.playerStateStream.listen(_onPlayerStateChanged);
    _subscribePosition();
    return engine;
  }

  /// 点击 segment 的播放按钮：**播放 / 暂停 / 继续**三态切换。
  ///
  /// - 当前段正在播放 → **暂停**（停在当前位置，**不回到开头**）；
  /// - 当前段已暂停 → **继续**（从断点续播；已播到段尾则从头开始）；
  /// - 点了另一个段 → seek 到该段起点播放。
  Future<void> playSegment({
    required String meetingId,
    required String segmentId,
    required int startMs,
    required int endMs,
  }) async {
      _endMs = endMs;

      // 正在播当前段 → 暂停，保留断点。
      if (state.isSegmentPlaying(segmentId, startMs)) {
        await pause();
        return;
      }
      // 先立意图，再调 play：防止迟到/回放的 playing=false 事件把状态打回。
      _intentPlaying = true;
    try {
      final BackendApi api = await _ensureApi();
      final String? path = await api.getAudioPath(meetingId);
      if (path == null || path.isEmpty) {
        _toast('录音结束后即可回放该片段（音频尚未归档）');
        return;
      }

      final bool sameSource = state.currentMeetingId == meetingId;
      if (!sameSource) {
        final Duration? duration = await _player.setFilePath(path);
        state = state.copyWith(
          currentMeetingId: meetingId,
          durationMs: duration?.inMilliseconds ?? 0,
          clearError: true,
        );
      }

      // 续播：停在本段中间 → 从断点继续；已播到段尾 → 从头开始。
      final int resumedMs = state.isSegmentActive(segmentId, startMs)
          ? _resumePositionMs(startMs: startMs, endMs: endMs)
          : startMs;
      final int targetMs = clampSeekMs(resumedMs, state.durationMs);
      await _player.seek(Duration(milliseconds: targetMs));
      await _player.play();

      state = state.copyWith(
        playingSegmentId: segmentId,
        playingStartMs: startMs,
        isPlaying: true,
        currentPositionMs: targetMs,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isPlaying: false, error: '播放失败：$error');
      _toast('播放失败：$error', tone: ToastTone.warning);
    }
  }

  /// 暂停当前播放（保留位置，供下次续播）。
  Future<void> pause() async {
    _intentPlaying = false;
    try {
      await _player.pause();
    } catch (_) {
      // ignore
    }
    state = state.copyWith(isPlaying: false);
  }

  /// 续播位置：断点在段内 → 断点；已播到段尾（80ms 容差）→ 段起点。
  int _resumePositionMs({required int startMs, required int endMs}) {
    final int position = state.currentPositionMs;
    if (position < startMs) return startMs;
    if (position >= endMs - 80) return startMs;
    return position;
  }

  /// 外部切页/手动停止时调用。
  Future<void> stop() async {
    try {
      await _player.pause();
    } catch (_) {
      // ignore
    }
    state = state.copyWith(isPlaying: false);
  }

  Future<BackendApi> _ensureApi() async {
    final BackendApi? api = _api;
    if (api != null) return api;
    final BackendApi resolved = await ref.read(backendProvider.future);
    _api = resolved;
    return resolved;
  }

  void _onPlayerStateChanged(PlayerState playerState) {
    if (_disposed) return;
    // 播到文件末尾：撤下播放组件。
    if (playerState.processingState == ProcessingState.completed) {
      _intentPlaying = false;
      state = state.copyWith(isPlaying: false, clearActive: true);
      return;
    }
    if (playerState.playing) {
      // 外部/播放器自行开播：同步为播放中。
      if (!state.isPlaying) state = state.copyWith(isPlaying: true);
      return;
    }
    // 与意图相反的迟到事件（首次订阅回放的典型表现）→ 忽略，避免把组件打没。
    if (_intentPlaying) return;
    if (state.isPlaying) state = state.copyWith(isPlaying: false);
  }

  void _subscribePosition() {
    _positionSub?.cancel();
    _positionSub = _player.positionStream.listen((Duration position) {
      if (_disposed) return;
      final int ms = position.inMilliseconds;
      state = state.copyWith(currentPositionMs: ms);
      if (_endMs > 0 && ms >= _endMs && state.isPlaying) {
        _autoStop();
      }
    });
  }

  Future<void> _autoStop() async {
    _intentPlaying = false;
    try {
      await _player.pause();
    } catch (_) {
      // ignore
    }
    // 播完即清除「当前段」：进度条与「已播 / 段长」整块撤下，避免上一段的
    // 播放组件残留导致下一段点播时布局错位。
    state = state.copyWith(isPlaying: false, clearActive: true);
  }

  void _toast(String text, {ToastTone tone = ToastTone.info}) {
    ref.read(toastProvider.notifier).show(text, tone: tone);
  }

  Future<void> _dispose() async {
    _disposed = true;
    await _positionSub?.cancel();
    _positionSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _player.dispose();
    } catch (_) {
      // ignore
    }
    _resolvedEngine = null;
  }

  /// 测试钩子：观察内部结束时间。
  int get endMsForTest => _endMs;
}

/// 音频播放器 provider（页面级生命周期）。
final NotifierProvider<AudioPlayerController, AudioPlayerState>
    audioPlayerControllerProvider =
    NotifierProvider<AudioPlayerController, AudioPlayerState>(
  () => AudioPlayerController(),
);
