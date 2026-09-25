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
      expect(container.read(audioPlayerControllerProvider).isSegmentPlaying('s1'), isTrue);
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

    test('播放到 endMs 自动暂停', () async {
      final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
      final ProviderContainer container = _boot(engine: engine, audioPath: '/tmp/m.wav');
      addTearDown(container.dispose);

      final AudioPlayerController ctrl = container.read(audioPlayerControllerProvider.notifier);
      await ctrl.playSegment(meetingId: 'm1', segmentId: 's1', startMs: 1000, endMs: 5000);
      engine.tickTo(5100);
      await Future<void>.delayed(Duration.zero);

      expect(engine.pauseCalls, greaterThanOrEqualTo(1));
      expect(container.read(audioPlayerControllerProvider).isPlaying, isFalse);
    });
  });
}
