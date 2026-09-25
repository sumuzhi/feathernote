/// PCM16LE 能量计量：**判断「麦克风到底有没有采到声音」**。
///
/// 存在的理由（对应一个真实线上事故）：
/// 录音页显示「录音中」、字节计数持续增长、`已录时长` 也在涨，但实时转写只出几秒
/// 就再无输出、会后终稿报 `ASR_RESPONSE_HAVE_NO_WORDS`。把设备上归档的 WAV 拉下来
/// 做能量分析后发现：字节流确实填满 **8.76s**，但前 **2.78s** 有真实波形
/// （peak 1944→6255），之后到结束 **100% 是 0**，尾部甚至是
/// `2,2,-2,-2,...,0,0,0` —— 即底层 `AudioRecord` 实际已哑掉，只是还在按字节填充。
///
/// 结论：**「有没有收到 chunk」不等于「有没有采到声音」**。此前看门狗只看前者，
/// 所以这类「静音流」永远不会被发现。本文件提供后者。
///
/// 设计约束：
/// - 纯 Dart、零依赖（`dart:typed_data` 即可），不引入任何 package；
/// - 同步、无分配热点：每 chunk 一次线性扫描，20ms/640B 下开销可忽略；
/// - 对畸形输入（空 / 长度 < 2 / 奇数长度）安全返回零值，绝不抛异常。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 静音判定阈值（16bit 有符号采样绝对值）。
///
/// 取值依据（实测样本，非拍脑袋）：
/// - 真实语音：peak 1944 – 6255（rms 181 – 667）；
/// - 采集链路哑掉后的数字静音：peak 为 **2**（仅 ±2 LSB 的底噪）。
///
/// 取 150 与两边都留出**约一个数量级**余量：既不会把小声说话误判为静音，
/// 也不会把底噪当成有效信号。
const int kSilencePeakThreshold = 150;

/// 一段 PCM 的能量读数。
class PcmLevel {
  /// 构造读数。
  const PcmLevel({required this.rms, required this.peak});

  /// 零能量读数（空 / 静音 PCM）。
  const PcmLevel.silent() : rms = 0, peak = 0;

  /// 均方根幅度（0 – 32768）。
  final double rms;

  /// 绝对值峰值（0 – 32768）。
  final int peak;

  /// 是否判为静音。
  ///
  /// 只看 [peak]：`rms` 会被长时间低电平拉低，而「麦克风有没有信号」这件事
  /// 由峰值决定（哪怕只有一瞬间有声音，也算采到了）。
  bool get isSilent => peak < kSilencePeakThreshold;

  @override
  String toString() => 'PcmLevel(peak=$peak, rms=${rms.toStringAsFixed(1)})';
}

/// 测量一段 **PCM16LE 小端** 单声道数据的能量。
///
/// [pcm] 长度不足 2 字节或为奇数时返回 [PcmLevel.silent]（不抛异常）。
/// 末尾不足 2 字节的残余字节会被忽略。
PcmLevel measurePcm(Uint8List pcm) {
  final int usable = pcm.length - (pcm.length % 2);
  if (usable < 2) return const PcmLevel.silent();

  final ByteData view = ByteData.view(pcm.buffer, pcm.offsetInBytes, usable);
  int peak = 0;
  double sumSquares = 0;
  int count = 0;
  for (int i = 0; i + 1 < usable; i += 2) {
    final int sample = view.getInt16(i, Endian.little);
    final int abs = sample < 0 ? -sample : sample;
    if (abs > peak) peak = abs;
    sumSquares += sample * sample;
    count++;
  }
  if (count == 0) return const PcmLevel.silent();
  return PcmLevel(rms: math.sqrt(sumSquares / count), peak: peak);
}
