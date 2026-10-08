/// 回归固化：**收尾日志里的「后端落盘字节」不得因会话读数被清空而打成 0**。
///
/// 历史缺陷（真机日志）：
/// ```
/// [recorder] 收尾总账 … 上送=348160B 后端落盘=348160B   ← 正确
/// [recorder] 收尾·后端 stopRecording 完成 … 后端落盘=0B   ← 错误（误导排查）
/// ```
/// 根因：`RecorderController.stopAndGenerate()` 在 `await api.stopRecording()` **之后**
/// 才读 `api.activePcmBytes`，而 `BackendApiImpl.stopRecording` 收尾时会把
/// `_activeSessionId` 置 null → `activePcmBytes` 恒返回 0。
///
/// 契约（本测试固化）：
/// - 同一次收尾中，「收尾总账」与「stopRecording 完成」两行打印的字节数**必须一致**；
/// - 且 == stop **之前**捕获的真实值（本用例 6400B），**不得为 0**。
///
/// 假后端刻意模拟「stop 之后 `activePcmBytes` 变 0」的真实语义：
/// 因此若把读取时机改回 stop 之后，本测试必然失败。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
import 'package:smart_minutes_flutter/backend/services/transcription_service.dart';
import 'package:smart_minutes_flutter/core/log/log.dart';
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

/// 从日志行提取「后端落盘=N B」的字节数；无匹配返回 null。
int? _extractPcmBytes(String line) {
  final RegExpMatch? match = RegExp(r'后端落盘=(-?\d+)B').firstMatch(line);
  return match == null ? null : int.parse(match.group(1)!);
}

/// 可控的假麦克风（只需能起流并推数据）。
class _FakeMic implements MicSource {
  final List<StreamController<Uint8List>> streams = <StreamController<Uint8List>>[];

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isPcmSupported() async => true;

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRateHz,
    required int channels,
  }) async {
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
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// 假后端：**模拟真实语义** —— `stopRecording` 之后会话读数被清空（`activePcmBytes` → 0）。
class _SessionClearingBackend implements BackendApi {

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

  /// 是否已停止（= 真实实现里 `_activeSessionId` 被置 null）。
  bool _stopped = false;

  @override
  int get activePcmBytes =>
      // stop 之前返回真实落盘量；stop 之后返回 0（复现被清空的会话读数）。
      _stopped ? 0 : frames.fold<int>(0, (int sum, AudioFrame f) => sum + f.pcm.length);

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
  }) async {}

  @override
  void pushAudioFrame(AudioFrame frame) => frames.add(frame);

  @override
  Future<Meeting?> stopRecording(String meetingId) async {
    stopCalls++;
    _stopped = true; // 复现：stop 后活动会话被清空 → 读数归 0。
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(clearLogHistory);
  tearDown(clearLogHistory);

  test('收尾日志「后端落盘」在 stop 前后必须一致，且事后不被打成 0', () async {
    final _FakeMic mic = _FakeMic();
    final _SessionClearingBackend backend = _SessionClearingBackend();
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

    // 推 2 × 100ms 静音 = 10 帧 × 640B = 6400B（真实落盘量）。
    mic.emit(_silence(100));
    await _settle();
    mic.emit(_silence(100));
    await _settle();
    expect(backend.frames.length, 10);
    const int expectedPcmBytes = 10 * 640;
    expect(backend.activePcmBytes, expectedPcmBytes, reason: 'stop 前的落盘量');

    final String? meetingId = await rec.stopAndGenerate();
    await _settle();
    expect(meetingId, 'm1');
    expect(backend.stopCalls, 1);

    // 取样两行日志。
    final List<String> logs = recentLogs();
    final String totalLine =
        logs.firstWhere((String l) => l.contains('收尾总账'), orElse: () => '');
    final String stopLine = logs.firstWhere(
      (String l) => l.contains('收尾·后端 stopRecording 完成'),
      orElse: () => '',
    );
    expect(totalLine, isNotEmpty, reason: '必须有「收尾总账」日志');
    expect(stopLine, isNotEmpty, reason: '必须有「stopRecording 完成」日志');

    final int? totalBytes = _extractPcmBytes(totalLine);
    final int? stopBytes = _extractPcmBytes(stopLine);
    expect(totalBytes, expectedPcmBytes, reason: '收尾总账=stop 前真实落盘量');
    expect(
      stopBytes,
      totalBytes,
      reason: 'stop 完成后不得因会话读数被清空而打成 0（两行必须一致）',
    );
    expect(stopBytes, isNot(0), reason: '确实录了音，绝不能被误报为 0B');
  });
}
