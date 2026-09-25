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
    this.isPlaying = false,
    this.currentPositionMs = 0,
    this.durationMs = 0,
    this.currentMeetingId,
    this.error,
  });

  /// 当前正在播放（或最后播放）的 segmentId。
  final String? playingSegmentId;

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
  bool isSegmentPlaying(String segmentId) =>
      playingSegmentId == segmentId && isPlaying;

  /// 复制并替换部分字段。
  AudioPlayerState copyWith({
    String? playingSegmentId,
    bool? isPlaying,
    int? currentPositionMs,
    int? durationMs,
    String? currentMeetingId,
    String? error,
    bool clearError = false,
  }) =>
      AudioPlayerState(
        playingSegmentId: playingSegmentId ?? this.playingSegmentId,
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

  /// 播放指定 segment。
  Future<void> playSegment({
    required String meetingId,
    required String segmentId,
    required int startMs,
    required int endMs,
  }) async {
    _endMs = endMs;
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

      final int targetMs = clampSeekMs(startMs, state.durationMs);
      await _player.seek(Duration(milliseconds: targetMs));
      await _player.play();

      state = state.copyWith(
        playingSegmentId: segmentId,
        isPlaying: true,
        currentPositionMs: targetMs,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isPlaying: false, error: '播放失败：$error');
      _toast('播放失败：$error', tone: ToastTone.warning);
    }
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
    final bool playing = playerState.playing;
    if (state.isPlaying != playing) {
      state = state.copyWith(isPlaying: playing);
    }
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
    try {
      await _player.pause();
    } catch (_) {
      // ignore
    }
    state = state.copyWith(isPlaying: false);
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
