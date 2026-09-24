/// 采样率兜底重采样器（线性插值）。
///
/// **U1 改道**：`record` 请求 16000Hz 可能被设备拒绝并静默降级，
/// 此时在 Dart 侧把实际采样率转换为 16000Hz 再喂给百炼，
/// 并把**实际采样率**写入 `meetings.sample_rate`（保证 WAV 头正确）。
library;

import 'dart:typed_data';

/// 线性插值重采样器（16bit 小端 PCM）。
class Resampler {
  /// 构造重采样器。
  ///
  /// [fromHz] 源采样率，[toHz] 目标采样率；两者相等时 [convert] 原样返回输入。
  Resampler({required this.fromHz, required this.toHz})
    : assert(fromHz > 0, 'fromHz 必须为正'),
      assert(toHz > 0, 'toHz 必须为正');

  /// 源采样率。
  final int fromHz;

  /// 目标采样率。
  final int toHz;

  /// 是否需要转换。
  bool get needed => fromHz != toHz;

  /// 转换 PCM；输出样本数 = `floor(输入样本数 × toHz / fromHz)`。
  ///
  /// 输入长度不足 2 字节或为奇数时，仅处理完整的样本对。
  Uint8List convert(Uint8List pcm16le) {
    if (!needed) return pcm16le;
    final int usable = pcm16le.length - (pcm16le.length % 2);
    final int inSamples = usable ~/ 2;
    if (inSamples == 0) return Uint8List(0);
    final int outSamples = (inSamples * toHz / fromHz).floor();
    if (outSamples <= 0) return Uint8List(0);

    final ByteData inView = ByteData.view(pcm16le.buffer, pcm16le.offsetInBytes, pcm16le.length);
    final Uint8List out = Uint8List(outSamples * 2);
    final ByteData outView = ByteData.view(out.buffer, out.offsetInBytes);

    final double ratio = fromHz / toHz;
    for (int i = 0; i < outSamples; i++) {
      final double srcPos = i * ratio;
      final int index = srcPos.floor();
      final double frac = srcPos - index;
      final int s0 = index < inSamples ? inView.getInt16(index * 2, Endian.little) : 0;
      final int s1 = index + 1 < inSamples ? inView.getInt16((index + 1) * 2, Endian.little) : s0;
      final double value = s0 + (s1 - s0) * frac;
      final int clamped = value.round().clamp(-32768, 32767);
      outView.setInt16(i * 2, clamped, Endian.little);
    }
    return out;
  }
}
