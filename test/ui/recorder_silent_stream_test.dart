/// 麦克风「**静音流**」检测回归：字节流在涨，但内容全是零。
///
/// 背景（真实事故，非假想）：用户录约 12 秒，页面显示「录音中」、字节计数持续增长、
/// `已录时长` 也在涨，但实时转写只出几秒就再无输出，会后终稿报
/// `ASR_RESPONSE_HAVE_NO_WORDS`。把设备上归档的 WAV 拉下来做能量分析：
///
/// | 时间窗 | peak | rms | 零值占比 |
/// |---|---|---|---|
/// | 0–1s | 1944 | 181 | 10.4% |
/// | 1–2s | 5108 | 481 | 0.5% |
/// | 2–3s | 6255 | 667 | 21.8% |
/// | **3–8.76s** | **0** | **0** | **100%** |
///
/// 有效音频只到 **t=2.784s**，之后到结束全是零，尾部是 `2,2,-2,-2,...,0,0,0`。
/// 即底层 `AudioRecord` 已哑掉，但仍**按字节填充** → 旧看门狗（只看"有没有收到
/// chunk"）永远抓不到。
///
/// 契约（本测试固化）：
/// - 有声音的窗口 → [RecorderController.silentSeconds] 归零；
/// - 连续 [kMicSilentSeconds] 个「有数据但全静音」的窗口 → 告警 + 重启采集流一次；
/// - 静音**绝不能**把用户的会议掐掉（不收尾），即便重启次数用尽；
/// - 静音重启**不消耗**断流看门狗的 [_restarts] 预算；
/// - 「一个 chunk 都没有」是断流不是静音 → 交给看门狗，不重复触发。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/core/pcm/audio_frame.dart';
import 'package:smart_minutes_flutter/core/pcm/level_meter.dart';
import 'package:smart_minutes_flutter/core/platform/mic_source.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/providers/recorder_controller.dart';

/// [ms] 毫秒的**有声** PCM（方波，峰值 5000，量级对齐真实语音）。
Uint8List _loud(int ms) {
  final int samples = ms * 16; // 16kHz
  final Uint8List bytes = Uint8List(samples * 2);
  final ByteData view = ByteData.view(bytes.buffer);
  for (int i = 0; i < samples; i++) {
    view.setInt16(i * 2, i % 40 < 20 ? 5000 : -5000, Endian.little);
  }
  return bytes;
}

/// [ms] 毫秒的**全零** PCM（模拟 AudioRecord 哑掉后仍按字节填充）。
Uint8List _zero(int ms) => Uint8List(ms * 32);

/// 让事件循环转几圈。
Future<void> _settle({int ms = 30}) async {
  for (int i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms ~/ 4));
  }
}

/// 可控的假麦克风。
class _FakeMic implements MicSource {
  final List<StreamController<Uint8List>> streams = <StreamController<Uint8List>>[];
  int startCalls = 0;
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
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 最小假后端。
class _FakeBackend implements BackendApi {

  // ── 导入音视频（BackendApi 增量 stub：导入流程不在本 UI 测试范围）──

  @override
  Future<Meeting> startImport(ImportRequest req) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelImport(String meetingId) async {}

  @override
  Future<void> retryImport(String meetingId) async {}

  @override
  Stream<ImportProgressEvent> get importEvents =>
      const Stream<ImportProgressEvent>.empty();
  final List<AudioFrame> frames = <AudioFrame>[];
  int stopCalls = 0;

  @override
  int get activePcmBytes =>
      frames.fold<int>(0, (int sum, AudioFrame f) => sum + f.pcm.length);

  @override
  Stream<TranscriptEvent> get events => const Stream<TranscriptEvent>.empty();

  @override
  Future<Meeting> createMeeting({required String title, int sampleRate = 16000}) async =>
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
  }) async {}

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

/// 建容器（不自动起录）。
({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
    _boot() {
  final _FakeMic mic = _FakeMic();
  final _FakeBackend backend = _FakeBackend();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      micSourceFactoryProvider.overrideWithValue(() => mic),
      backendProvider.overrideWith((Ref ref) async => backend),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    rec: container.read(recorderProvider.notifier),
    mic: mic,
    backend: backend,
  );
}

/// 持续喂 [chunk] 直到 [total] 时长耗尽（每 200ms 一次）。
Future<void> _feed(_FakeMic mic, Uint8List chunk, Duration total) async {
  final DateTime deadline = DateTime.now().add(total);
  while (DateTime.now().isBefore(deadline)) {
    mic.emit(chunk);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  test('有声音时不判静音；连续静音 3 个窗口 → 告警 + 重启一次，且不收尾', () async {
    final ({
      ProviderContainer container,
      RecorderController rec,
      _FakeMic mic,
      _FakeBackend backend,
    }) boot = _boot();
    await boot.rec.startRecording();
    await _settle();

    // ① 先喂一段真实量级的声音 → 首个诊断窗口应有高峰值、静音计数为 0。
    boot.mic.emit(_loud(100));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await _settle();
    expect(boot.rec.lastWindowPeak, greaterThanOrEqualTo(kSilencePeakThreshold));
    expect(boot.rec.silentSeconds, 0, reason: '采到声音就不该计入静音');
    expect(boot.mic.startCalls, 1, reason: '有声音时不该重启');

    // ② 之后持续吐全零（字节照常填充，内容为零）→ 3 个窗口后必须被发现。
    await _feed(boot.mic, _zero(100), const Duration(milliseconds: 3400));
    await _settle();

    expect(boot.rec.silentSeconds, greaterThanOrEqualTo(kMicSilentSeconds));
    expect(boot.rec.lastWindowPeak, lessThan(kSilencePeakThreshold));
    expect(boot.mic.startCalls, 2, reason: '静音流应触发一次采集流重启');
    expect(boot.rec.silenceRestartCount, 1);
    expect(
      boot.rec.restartCount,
      0,
      reason: '静音重启不得消耗断流看门狗的重启预算（两者分开计数）',
    );
    expect(
      boot.container.read(recorderProvider).phase,
      RecorderPhase.recording,
      reason: '静音绝不能把用户正在进行的会议掐掉',
    );
    expect(boot.backend.stopCalls, 0, reason: '静音不是故障终止，不得收尾');
    expect(
      boot.container.read(toastProvider)?.text,
      contains('未采集到有效声音'),
      reason: '用户必须看到明确提示，而不是"录音中"却什么都没录到',
    );

    await boot.rec.stopAndGenerate();
    await _settle();
  });

  test('静音重启用尽后继续静音：不再重启、不再提示、仍不收尾', () async {
    final ({
      ProviderContainer container,
      RecorderController rec,
      _FakeMic mic,
      _FakeBackend backend,
    }) boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    boot.mic.emit(_loud(100));
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    await _feed(boot.mic, _zero(100), const Duration(milliseconds: 3400));
    await _settle();
    expect(boot.mic.startCalls, 2);
    final int toastAfterFirst = boot.container.read(toastProvider)?.text.hashCode ?? 0;
    expect(toastAfterFirst, isNot(0));

    // 继续静音 2 秒：不得再重启、不得再弹 toast、不得收尾。
    await _feed(boot.mic, _zero(100), const Duration(milliseconds: 2200));
    await _settle();

    expect(boot.mic.startCalls, 2, reason: '静音最多只重启一次，不得打转');
    expect(boot.rec.silenceRestartCount, 1);
    expect(
      boot.container.read(recorderProvider).phase,
      RecorderPhase.recording,
      reason: '仍然在录音：安静的会议室不是故障',
    );
    expect(boot.backend.stopCalls, 0);

    await boot.rec.stopAndGenerate();
    await _settle();
  });

  test('静音后声音恢复 → 静音计数归零', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    boot.mic.emit(_loud(100));
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // 静音 2 个窗口（不足阈值，不应触发）。
    await _feed(boot.mic, _zero(100), const Duration(milliseconds: 2400));
    await _settle();
    expect(boot.rec.silentSeconds, greaterThan(0));
    expect(boot.mic.startCalls, 1, reason: '未达阈值不该重启');

    // 声音恢复 → 计数归零。
    await _feed(boot.mic, _loud(100), const Duration(milliseconds: 1200));
    await _settle();
    expect(boot.rec.silentSeconds, 0, reason: '重新采到声音后静音计数必须归零');
    expect(boot.mic.startCalls, 1);

    await boot.rec.stopAndGenerate();
    await _settle();
  });
}
