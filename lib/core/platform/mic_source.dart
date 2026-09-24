/// 麦克风采集抽象：把 `record` 插件隔离在一个薄适配层后面。
///
/// 抽出接口有三个目的：
/// 1. **可测**：`flutter test` 环境没有麦克风硬件，注入假实现即可驱动完整的
///    录音状态机（起流 → 收帧 → 停止），从而覆盖「结束并生成」的状态迁移；
/// 2. **可诊断**：起流 / 停流 / 权限 / 编码器支持收敛到一处，便于统一埋点；
/// 3. **可替换**：将来换插件或加 U1 采样率探测，只改这一层。
library;

import 'dart:typed_data';

import 'package:record/record.dart';

/// 麦克风来源。
abstract class MicSource {
  /// 是否已获得（必要时申请）麦克风权限。
  Future<bool> hasPermission();

  /// 当前设备 / 平台是否支持 `pcm16bits` 采集。
  ///
  /// 不支持时应当给出可读错误，而不是起流后静默无数据。
  Future<bool> isPcmSupported();

  /// 开始采集，返回 PCM16LE 单声道字节流。
  Future<Stream<Uint8List>> startStream({
    required int sampleRateHz,
    required int channels,
  });

  /// 暂停采集。
  Future<void> pause();

  /// 继续采集。
  Future<void> resume();

  /// 停止采集。
  Future<void> stop();

  /// 释放底层资源。
  Future<void> dispose();
}

/// 基于 `record` 插件的真实实现。
class RecordMicSource implements MicSource {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> isPcmSupported() =>
      _recorder.isEncoderSupported(AudioEncoder.pcm16bits);

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRateHz,
    required int channels,
  }) {
    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRateHz,
        numChannels: channels,
        // U3：固定新实现（advanced recorder），legacy 仅供极端兼容场景。
        androidConfig: const AndroidRecordConfig(useLegacy: false),
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}
