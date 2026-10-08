/// Bug 1 回归：录音「只录到 1 秒」的三重防线。
///
/// 用假 [MicSource] + 假 [BackendApi] 驱动真实录音状态机，逐项验证：
/// 1. 音频记账（chunk / 帧 / 字节）在 **10 秒**模拟录音下逐级对齐 —— 也就是
///    用户手工「录 10 秒看 audio_bytes / WAV 时长」的等价机器证据；
/// 2. 输入流被意外关闭（`onDone`）→ 自动重启一次并继续收帧；
/// 3. 流**静默**断流（只是不再产数据，没有 error / done）→ 看门狗兜住；
/// 4. 重启次数用尽 → 自动收尾（保留已录内容）并回到待机，UI 不再假装在录音；
/// 5. 起流前的权限 / 编码器支持校验给出可读错误。
///
/// 为什么不套 `fakeAsync`：Dart 的 `StreamSubscription.cancel()` 返回的 Future
/// 无法由 `FakeAsync.flushMicrotasks()/elapse()` 驱动（实测恒不完成），而停录 /
/// 重启路径必然 `await subscription.cancel()`。因此这里用真实时钟（看门狗一条
/// 用例最多等 ~4s）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
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

/// [ms] 毫秒的**有声** PCM（方波，峰值 5000，量级对齐真实语音）。
///
/// 何时用哪个：只看「有没有字节流动」的用例用 [_silence] 即可；但凡断言
/// 「不该被静音检测/看门狗重启」，必须用 [_speech] —— 因为全零 PCM 在
/// 采集语义上就是静音流（`AudioRecord` 哑掉的表现），会被静音检测正确命中。
Uint8List _speech(int ms) {
  final int samples = ms * 16;
  final Uint8List bytes = Uint8List(samples * 2);
  final ByteData view = ByteData.view(bytes.buffer);
  for (int i = 0; i < samples; i++) {
    view.setInt16(i * 2, i % 40 < 20 ? 5000 : -5000, Endian.little);
  }
  return bytes;
}

/// 让事件循环转几圈（流事件 / 多段 await 链都靠它收敛）。
Future<void> _settle({int ms = 30}) async {
  for (int i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration(milliseconds: ms ~/ 4));
  }
}

/// 可控的假麦克风。
class _FakeMic implements MicSource {
  _FakeMic({this.permission = true, this.pcmSupported = true});

  final bool permission;
  final bool pcmSupported;

  final List<StreamController<Uint8List>> streams = <StreamController<Uint8List>>[];
  int startCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> isPcmSupported() async => pcmSupported;

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

  /// 推送一段 PCM。
  void emit(Uint8List bytes) => streams.last.add(bytes);

  /// 模拟「输入流被系统关闭」。
  Future<void> endStream() => streams.last.close();

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// 最小假后端（只覆盖录音链路用到的能力）。
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
  final StreamController<TranscriptEvent> eventsCtrl =
      StreamController<TranscriptEvent>.broadcast();
  int stopCalls = 0;

  @override
  int get activePcmBytes =>
      frames.fold<int>(0, (int sum, AudioFrame f) => sum + f.pcm.length);

  @override
  Stream<TranscriptEvent> get events => eventsCtrl.stream;

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
    _boot({_FakeMic? mic, _FakeBackend? backend}) {
  final _FakeMic resolvedMic = mic ?? _FakeMic();
  final _FakeBackend resolvedBackend = backend ?? _FakeBackend();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      micSourceFactoryProvider.overrideWithValue(() => resolvedMic),
      backendProvider.overrideWith((Ref ref) async => resolvedBackend),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    rec: container.read(recorderProvider.notifier),
    mic: resolvedMic,
    backend: resolvedBackend,
  );
}

void main() {
  test('录满 10 秒：chunk / 帧 / 字节逐级对齐（等价手工 audio_bytes 校验）', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.recording);

    // 10 秒 = 100 次 × 100ms（每次 5 帧）。
    for (int i = 0; i < 100; i++) {
      boot.mic.emit(_silence(100));
    }
    await _settle();

    // 100ms = 16000 × 0.1 × 2 = 3200B。
    expect(boot.rec.chunkCount, 100);
    expect(boot.rec.frameCount, 500);
    expect(boot.rec.pushedBytes, 320000, reason: '10 秒 16kHz/16bit/单声道 = 320,000B');
    expect(boot.backend.frames.length, 500, reason: '每帧都应上送到后端');
    expect(boot.backend.activePcmBytes, 320000, reason: '后端落盘字节数应与上送一致');
    expect(
      boot.rec.frameCount * 20,
      10000,
      reason: '帧数 × 20ms 应等于 10 秒 —— 即 WAV / 时长应覆盖真实录音时长',
    );

    // 收尾：会议 ID 正常返回，状态回到待机。
    final String? meetingId = await boot.rec.stopAndGenerate();
    await _settle();
    expect(meetingId, 'm1');
    expect(boot.backend.stopCalls, 1);
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.idle);
    expect(boot.mic.stopCalls, greaterThanOrEqualTo(1));
  });

  test('输入流被关闭（onDone）→ 自动重启一次并继续收帧', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();

    boot.mic.emit(_silence(100));
    await _settle();
    expect(boot.rec.frameCount, 5);
    expect(boot.mic.startCalls, 1);

    await boot.mic.endStream();
    await _settle();

    expect(boot.mic.startCalls, 2, reason: 'onDone 应触发一次自动重启');
    expect(boot.rec.restartCount, 1);
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.recording);

    boot.mic.emit(_silence(20));
    await _settle();
    expect(boot.rec.frameCount, 6, reason: '重启后应继续收帧');
  });

  test('重启次数用尽后再断流 → 自动收尾（保留内容）并回到待机', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    boot.mic.emit(_silence(100));
    await _settle();

    await boot.mic.endStream(); // 第 1 次断流 → 重启
    await _settle();
    expect(boot.mic.startCalls, 2);

    await boot.mic.endStream(); // 第 2 次断流 → 达到上限
    await _settle();

    expect(boot.mic.startCalls, 2, reason: '不应无限重启');
    expect(boot.backend.stopCalls, 1, reason: '应收尾本次会议以保留已录内容');
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.idle);
    expect(boot.mic.stopCalls, greaterThanOrEqualTo(1));
  });

  test('看门狗：3 秒没有数据（无 error / done）→ 自动重启', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    boot.mic.emit(_silence(100));
    await _settle();
    expect(boot.mic.startCalls, 1);

    // 之后完全不再产数据：等满看门狗阈值 + 余量。
    await Future<void>.delayed(
      const Duration(milliseconds: (kMicStallSeconds + 1) * 1000),
    );
    await _settle();

    expect(boot.mic.startCalls, 2, reason: '静默断流应由看门狗发现并重启');
    expect(boot.rec.restartCount, 1);
    expect(
      boot.container.read(recorderProvider).phase,
      RecorderPhase.recording,
      reason: '重启后应继续录音，而不是静默停在旧状态',
    );
  });

  test('数据正常时不误判：持续收帧不会被看门狗重启', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();

    // 用**有声** PCM：全零数据在采集语义上就是静音流，会被静音检测正确命中。
    // 这里要验证的是「持续收帧时看门狗不误判」，故填充必须是真实幅度。
    for (int i = 0; i < (kMicStallSeconds + 1); i++) {
      boot.mic.emit(_speech(100));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
    await _settle();

    expect(boot.mic.startCalls, 1, reason: '一直有（有声）数据就不该重启');
    expect(boot.rec.restartCount, 0);
    expect(boot.rec.silentSeconds, 0, reason: '采集到声音 → 静音计数必须保持为 0');
  });

  test('未授权麦克风 → 停在待机并给出可读错误，且不起流', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot(mic: _FakeMic(permission: false));
    await boot.rec.startRecording();
    await _settle();

    final RecorderUiState state = boot.container.read(recorderProvider);
    expect(state.phase, RecorderPhase.idle);
    expect(state.error, contains('麦克风权限'));
    expect(boot.mic.startCalls, 0);
  });

  test('设备不支持 PCM16 → 停在待机并给出可读错误，且不起流', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot(mic: _FakeMic(pcmSupported: false));
    await boot.rec.startRecording();
    await _settle();

    final RecorderUiState state = boot.container.read(recorderProvider);
    expect(state.phase, RecorderPhase.idle);
    expect(state.error, contains('PCM16'));
    expect(boot.mic.startCalls, 0);
  });

  test('暂停 / 继续：暂停期间停止计时，恢复后继续', () async {
    final ({ProviderContainer container, RecorderController rec, _FakeMic mic, _FakeBackend backend})
        boot = _boot();
    await boot.rec.startRecording();
    await _settle();
    boot.mic.emit(_silence(100));
    await _settle();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await boot.rec.togglePause();
    await _settle();
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.paused);
    expect(boot.mic.pauseCalls, 1);
    final int frozen = boot.rec.elapsedMs;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(boot.rec.elapsedMs, frozen, reason: '暂停期间不应继续计时');

    await boot.rec.togglePause();
    await _settle();
    expect(boot.container.read(recorderProvider).phase, RecorderPhase.recording);
    expect(boot.mic.resumeCalls, 1);

    // 收尾，避免遗留后台定时器。
    await boot.rec.discard();
    await _settle();
  });
}
