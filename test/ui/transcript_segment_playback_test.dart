/// 转写页逐段播放回归测试。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/providers/audio_player_controller.dart';
import 'package:smart_minutes_flutter/ui/utils/transcript_timeline.dart';

/// 可控假播放器引擎。
class _FakeEngine implements AudioPlayerEngine {
  String? lastPath;
  int? lastSeekMs;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int setFilePathCalls = 0;
  final StreamController<Duration> _positionCtrl = StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _stateCtrl = StreamController<PlayerState>.broadcast();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  Future<Duration?> setFilePath(String path) async {
    setFilePathCalls++;
    lastPath = path;
    return _duration;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _stateCtrl.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _stateCtrl.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    lastSeekMs = position.inMilliseconds;
    _position = position;
    _positionCtrl.add(_position);
  }

  @override
  Duration get currentPosition => _position;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;

  @override
  Future<void> dispose() async {
    await _positionCtrl.close();
    await _stateCtrl.close();
  }

  /// 模拟 just_audio 的 `startWith` 流：订阅后**回放**一次当前状态（可迟到）。
  void replayState(PlayerState state) => _stateCtrl.add(state);

  /// 模拟位置推进（用于自动停测试）。
  void tickTo(int ms) {
    _position = Duration(milliseconds: ms);
    _positionCtrl.add(_position);
  }

  set duration(Duration value) => _duration = value;
}

/// 最小假 BackendApi，只回答 getAudioPath。
class _FakeApi implements BackendApi {
  _FakeApi({this.audioPath});

  final String? audioPath;

  @override
  Future<String?> getAudioPath(String meetingId) async => audioPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _boot({
  required _FakeEngine engine,
  required String? audioPath,
}) =>
    ProviderContainer(
      overrides: [
        backendProvider.overrideWith((Ref ref) async => _FakeApi(audioPath: audioPath)),
        audioPlayerControllerProvider.overrideWith(
          () => AudioPlayerController(engine: engine),
        ),
      ],
    );

void main() {
  group('clampSeekMs', () {
    test('末尾 seek 被夹取到 duration-50ms，避免触发 ended', () {
      expect(clampSeekMs(10000, 10000), 9950);
      expect(clampSeekMs(12000, 10000), 9950);
    });

    test('负值归 0，正常值原样', () {
      expect(clampSeekMs(-100, 10000), 0);
      expect(clampSeekMs(5000, 10000), 5000);
    });

    test('duration <= 0 时返回 0', () {
      expect(clampSeekMs(100, 0), 0);
      expect(clampSeekMs(100, -1), 0);
    });
  });

  group('AudioPlayerController', () {
    test('playSegment 会加载文件、seek 到 clamp 后的 startMs、开始播放', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(
        meetingId: 'm1',
        segmentId: 's1',
        startMs: 1000,
        endMs: 5000,
      );

      expect(engine.lastPath, '/tmp/m.wav');
      expect(engine.lastSeekMs, 1000);
      expect(engine.playCalls, 1);
      expect(ctrl.endMsForTest, 5000);
      expect(container.read(audioPlayerControllerProvider).isSegmentPlaying('s1', 1000), isTrue);
    });

    test('同一会议切换 segment 不再重新 setFilePath', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.lastPath = null;
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's2', startMs: 6000, endMs: 9000);

      expect(engine.lastPath, isNull, reason: '同一会议应复用已加载的音源');
      expect(engine.lastSeekMs, 6000);
      expect(engine.playCalls, 2);
    });

    test('切换会议重新 setFilePath', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m1.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      await ctrl.playSegment(meetingId: 'm2', segmentId: 's2', startMs: 6000, endMs: 9000);

      expect(engine.lastPath, '/tmp/m1.wav');
      expect(engine.setFilePathCalls, 2);
    });

    test('音频未归档时给出提示且不调用播放器', () async {
      final _FakeEngine engine = _FakeEngine();
      final ProviderContainer container = _boot(engine: engine, audioPath: null);
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);

      expect(engine.setFilePathCalls, 0);
      expect(engine.playCalls, 0);
    });

    test('播放到 endMs 自动暂停，并清除「当前段」（播放组件整块撤下）', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      expect(container.read(audioPlayerControllerProvider).isSegmentActive('s1', 1000), isTrue);

      engine.tickTo(5100);
      await Future<void>.delayed(Duration.zero);

      expect(engine.pauseCalls, greaterThanOrEqualTo(1));
      expect(container.read(audioPlayerControllerProvider).isPlaying, isFalse);
      expect(
        container.read(audioPlayerControllerProvider).playingSegmentId,
        isNull,
        reason: '播完必须清除当前段，否则下一段点播时上一段的进度组件残留、布局错位',
      );
      expect(container.read(audioPlayerControllerProvider).isSegmentActive('s1', 1000), isFalse);
    });

    test('再次点击当前段 = 暂停（停在当前位置，不回到开头）', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.tickTo(3000);
      await Future<void>.delayed(Duration.zero);

      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);

      expect(engine.pauseCalls, greaterThanOrEqualTo(1));
      expect(container.read(audioPlayerControllerProvider).isPlaying, isFalse);
      expect(
        container.read(audioPlayerControllerProvider).isSegmentActive('s1', 1000),
        isTrue,
        reason: '暂停后仍是当前段（进度条保留）',
      );
      // 关键：暂停时不得再发起 seek（位置停在断点，不回到段首）。
      expect(engine.seekCalls, 1, reason: '暂停只应 pause，不得再 seek 回 1000');
      expect(container.read(audioPlayerControllerProvider).currentPositionMs, 3000);
    });

    test('暂停后再点击 = 从断点续播（不是从头）', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.tickTo(3000);
      await Future<void>.delayed(Duration.zero);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000); // 暂停

      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000); // 续播

      expect(engine.lastSeekMs, 3000, reason: '续播必须回到断点，不能回到 1000');
      expect(container.read(audioPlayerControllerProvider).isPlaying, isTrue);
    });

    test('已播到段尾后再点击 = 从头开始', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.tickTo(5000);
      await Future<void>.delayed(Duration.zero);

      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);

      expect(engine.lastSeekMs, 1000, reason: '播完后再点应从头开始');
    });
    test('segmentId 撞车（ASR 重启后编号归零）时仍能定位到正确的一段', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      // 前一段：seg_1 @ 1000
      await ctrl.playSegment(meetingId: 'm1', segmentId: 'seg_1', startMs: 1000, endMs: 2000);
      expect(container.read(audioPlayerControllerProvider).isSegmentActive('seg_1', 1000), isTrue);

      // 重启后服务端又把编号从 1 开始 → 又一个 seg_1，但起点 7000。
      await ctrl.playSegment(meetingId: 'm1', segmentId: 'seg_1', startMs: 7000, endMs: 9000);

      final AudioPlayerState state = container.read(audioPlayerControllerProvider);
      expect(state.isSegmentActive('seg_1', 7000), isTrue, reason: '当前段应是后一段');
      expect(state.isSegmentActive('seg_1', 1000), isFalse, reason: '旧的同 id 段不得再被认作当前段');
      expect(engine.lastSeekMs, 7000, reason: '必须 seek 到新段起点');
    });

    test('首次播放：播放器回放的迟到 playing=false 事件不得把组件打没', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      expect(
        container.read(audioPlayerControllerProvider).isSegmentPlaying('s1', 1000),
        isTrue,
        reason: '首次播放后播放组件必须出现（历史 bug：只在第一次不显示）',
      );

      // 模拟 just_audio 的 startWith 流在订阅后**迟到**回放的旧值。
      engine.replayState(PlayerState(false, ProcessingState.ready));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(audioPlayerControllerProvider).isSegmentPlaying('s1', 1000),
        isTrue,
        reason: '我们仍在播，迟到的 playing=false 必须被忽略',
      );
    });

    test('播放器 completed：清除当前段并置为未播放', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.replayState(PlayerState(false, ProcessingState.completed));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(audioPlayerControllerProvider).isPlaying, isFalse);
      expect(container.read(audioPlayerControllerProvider).playingSegmentId, isNull);
    });
  });
}
