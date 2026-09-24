/// 问题 1 回归：**暂停语义 = 停止采集 / 停止投递，但不丢已录数据**。
///
/// 契约：
/// - 暂停期间不接收新音频、不向后端投递新帧；
/// - 已录数据保留，恢复后**接续同一会话与同一 PCM 写流**（不新建 session）；
/// - 停录时帧序号连续无缺口（WAV / 时长覆盖实际录音总时长）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/core/pcm/audio_frame.dart';
import 'package:smart_minutes_flutter/core/platform/mic_source.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/providers/recorder_controller.dart';

/// [ms] 毫秒的静音 PCM（16kHz / 16bit / 单声道 = 32B/ms）。
Uint8List _silence(int ms) => Uint8List(ms * 16 * 2);

/// 让事件循环转几圈。
Future<void> _settle() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }
}

/// 可控的假麦克风（记录起流 / 暂停 / 恢复次数）。
class _FakeMic implements MicSource {
  final List<StreamController<Uint8List>> streams = <StreamController<Uint8List>>[];
  int startCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isPcmSupported() async => true;

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRateHz,
    required int channels,
  }) async {
    startCalls++;
    final StreamController<Uint8List> controller = StreamController<Uint8List>();
    streams.add(controller);
    return controller.stream;
  }

  void emit(Uint8List bytes) => streams.last.add(bytes);

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}
}

/// 假后端：记录上送帧与绑定过的 sessionId。
class _FakeBackend implements BackendApi {
  final List<AudioFrame> frames = <AudioFrame>[];
  final List<String> sessionIds = <String>[];
  int stopCalls = 0;

  @override
  int get activePcmBytes =>
      frames.fold<int>(0, (int sum, AudioFrame f) => sum + f.pcm.length);

  @override
  Stream<TranscriptEvent> get events => const Stream<TranscriptEvent>.empty();

  @override
  Future<Meeting> createMeeting({
    required String title,
    int sampleRate = 16000,
  }) async =>
      Meeting(
        id: 'm1',
        title: title,
        createdAt: DateTime(2026, 9, 24, 10),
        durationMs: 0,
        sampleRate: sampleRate,
        speakerCount: 0,
        status: MeetingStatus.recording,
        source: MeetingSource.microphone,
        finalizeStatus: FinalizeStatus.none,
        transcriptSource: TranscriptSource.realtime,
        audioStatus: AudioStatus.none,
        audioBytes: 0,
        minutesPartial: false,
        segments: const <TranscriptSegment>[],
        speakers: const <Speaker>[],
      );

  @override
  Future<void> startRecording({
    required String meetingId,
    required String sessionId,
    String? title,
  }) async =>
      sessionIds.add(sessionId);

  @override
  void pushAudioFrame(AudioFrame frame) => frames.add(frame);

  @override
  Future<Meeting?> stopRecording(String meetingId) async {
    stopCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('录→暂停→恢复→录→停：帧连续无缺口、不重建会话与麦克风流', () async {
    final _FakeMic mic = _FakeMic();
    final _FakeBackend backend = _FakeBackend();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        micSourceFactoryProvider.overrideWithValue(() => mic),
        backendProvider.overrideWith((Ref ref) async => backend),
      ],
    );
    addTearDown(container.dispose);
    final RecorderController rec = container.read(recorderProvider.notifier);

    await rec.startRecording();
    await _settle();
    expect(container.read(recorderProvider).phase, RecorderPhase.recording);

    // 第 1 段：5 帧。
    mic.emit(_silence(100));
    await _settle();
    expect(rec.frameCount, 5);
    expect(backend.frames.length, 5);

    // 暂停。
    await rec.togglePause();
    await _settle();
    expect(container.read(recorderProvider).phase, RecorderPhase.paused);
    expect(mic.pauseCalls, 1);

    // 暂停期间即使插件仍推数据，也**不得**投递后端、不得产新帧。
    mic.emit(_silence(100));
    await _settle();
    expect(rec.frameCount, 5, reason: '暂停期间不产新帧');
    expect(backend.frames.length, 5, reason: '暂停期间不得向后端投递新帧');

    // 恢复。
    await rec.togglePause();
    await _settle();
    expect(container.read(recorderProvider).phase, RecorderPhase.recording);
    expect(mic.resumeCalls, 1);

    // 第 2 段：继续 5 帧。
    mic.emit(_silence(100));
    await _settle();
    expect(rec.frameCount, 10, reason: '恢复后从同一 seq 接续');
    expect(backend.frames.length, 10);
    expect(backend.activePcmBytes, 6400, reason: '10 帧 × 640B，连续无缺口');

    // 帧序号必须严格连续 0..9（无截断 / 无重开）。
    expect(
      backend.frames.map((AudioFrame f) => f.seq).toList(),
      List<int>.generate(10, (int i) => i),
      reason: '恢复不得截断/重开 PCM 写流',
    );
    expect(mic.startCalls, 1, reason: '暂停/恢复不得重建麦克风流');
    expect(backend.sessionIds.length, 1, reason: '一次录音只应有一个会话');
    expect(backend.sessionIds.toSet().length, 1, reason: '不得新建 session');

    final String? meetingId = await rec.stopAndGenerate();
    await _settle();
    expect(meetingId, 'm1');
    expect(backend.stopCalls, 1);
    expect(container.read(recorderProvider).phase, RecorderPhase.idle);
  });
}
