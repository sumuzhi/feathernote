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

import '../log/log.dart';

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
  Future<bool> hasPermission() async {
    // `record` 的 hasPermission() 默认 request=true：权限缺失时会主动弹窗申请。
    final bool granted = await _recorder.hasPermission();
    logInfo('mic', '权限询问 hasPermission(request=默认true) 结果=$granted');
    return granted;
  }

  @override
  Future<bool> isPcmSupported() async {
    final bool ok = await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
    logInfo('mic', '编码器支持检测 encoder=pcm16bits 结果=$ok');
    return ok;
  }

  @override
  Future<Stream<Uint8List>> startStream({
    required int sampleRateHz,
    required int channels,
  }) async {
    logInfo(
      'mic',
      '打开 PCM 流',
      <String, Object?>{
        'sampleRate': sampleRateHz,
        'channels': channels,
        'encoder': 'pcm16bits',
        'androidLegacy': false,
      },
    );
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Stream<Uint8List> stream = await _recorder.startStream(
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
      logInfo('mic', 'PCM 流已打开 耗时=${watch.elapsedMilliseconds}ms');
      return stream;
    } catch (error) {
      logWarn('mic', '打开 PCM 流失败 耗时=${watch.elapsedMilliseconds}ms：$error');
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _recorder.pause();
      logInfo('mic', '采集已暂停');
    } catch (error) {
      logWarn('mic', '暂停失败：$error');
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _recorder.resume();
      logInfo('mic', '采集已继续');
    } catch (error) {
      logWarn('mic', '继续失败：$error');
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _recorder.stop();
      logInfo('mic', '采集已停止（流关闭）');
    } catch (error) {
      logWarn('mic', '停止采集失败：$error');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
      logInfo('mic', '麦克风资源已释放');
    } catch (error) {
      logWarn('mic', '释放麦克风失败：$error');
      rethrow;
    }
  }
}
