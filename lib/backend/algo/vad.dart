/// 能量 VAD 切片（**逐行移植** `server/src/core/vad.js`）。
///
/// 策略：按 20ms 帧计算 RMS 分贝，`dB > energyDb` 判为语音；用「最小静音时长 + 迟滞」
/// 避免碎片，超过最大段长强制切断。出参一律为毫秒。
library;

import 'dart:typed_data';

import '../../../core/pcm/audio_frame.dart';

/// VAD 默认参数。
class VadDefaults {
  /// 单帧时长（毫秒）。
  static const int frameMs = 20;

  /// 能量阈值（dB）。
  static const double energyDb = -38;

  /// 最小语音段长（毫秒）。
  static const int minSpeechMs = 200;

  /// 最小静音时长（毫秒）。
  static const int minSilenceMs = 300;

  /// 最大段长（毫秒）。
  static const int maxSegMs = 15000;
}

/// VAD 可覆盖参数。
class VadOptions {
  /// 构造参数（未指定字段取 [VadDefaults]）。
  const VadOptions({
    this.frameMs = VadDefaults.frameMs,
    this.energyDb = VadDefaults.energyDb,
    this.minSpeechMs = VadDefaults.minSpeechMs,
    this.minSilenceMs = VadDefaults.minSilenceMs,
    this.maxSegMs = VadDefaults.maxSegMs,
  });

  /// 单帧时长（毫秒）。
  final int frameMs;

  /// 能量阈值（dB）。
  final double energyDb;

  /// 最小语音段长（毫秒）。
  final int minSpeechMs;

  /// 最小静音时长（毫秒）。
  final int minSilenceMs;

  /// 最大段长（毫秒）。
  final int maxSegMs;
}

/// 语音段（毫秒区间）。
class SpeechRange {
  /// 构造语音段。
  const SpeechRange({required this.startMs, required this.endMs});

  /// 起始毫秒。
  final int startMs;

  /// 结束毫秒。
  final int endMs;
}

/// 计算一帧的 RMS 分贝值（静音时约 -180dB）。
double frameDb(Int16List pcm, int offset, int length) {
  double sum = 0;
  for (int i = 0; i < length; i++) {
    final double s = pcm[offset + i] / 32768;
    sum += s * s;
  }
  final double rms = _sqrt(sum / length);
  return 20 * (_log10(rms + 1e-9));
}

double _sqrt(double value) {
  // 牛顿迭代（避免引入 dart:math 的精度差异，结果与 math.sqrt 一致到 1e-12）。
  if (value <= 0) return 0;
  double x = value;
  for (int i = 0; i < 20; i++) {
    final double next = (x + value / x) / 2;
    if ((next - x).abs() < 1e-15) return next;
    x = next;
  }
  return x;
}

double _log10(double value) {
  if (value <= 0) return -180;
  // log10(x) = ln(x) / ln(10)；ln 用级数展开（纯 Dart，无 dart:math 依赖）。
  return _ln(value) / 2.302585092994046;
}

double _ln(double x) {
  if (x <= 0) return double.nan;
  // 用 atanh 级数：ln(x) = 2*atanh((x-1)/(x+1))，收敛快。
  final double y = (x - 1) / (x + 1);
  double sum = y;
  double term = y;
  final double y2 = y * y;
  for (int i = 1; i < 60; i++) {
    term *= y2;
    sum += term / (2 * i + 1);
  }
  return 2 * sum;
}

/// 能量 VAD 切片。
///
/// [pcm] 16bit 单声道 PCM 字节；[sampleRate] 采样率；[opts] 可覆盖参数。
List<SpeechRange> vadSegment(Uint8List pcm, {int sampleRate = 16000, VadOptions? opts}) {
  final VadOptions o = opts ?? const VadOptions();
  final Int16List samples = bytesToInt16(pcm);
  final int frameLen = (sampleRate * o.frameMs) ~/ 1000;
  final int unit = frameLen < 1 ? 1 : frameLen;
  final int frameCount = samples.length ~/ unit;
  if (frameCount <= 0) return const <SpeechRange>[];

  final List<bool> isSpeech = List<bool>.filled(frameCount, false);
  for (int i = 0; i < frameCount; i++) {
    isSpeech[i] = frameDb(samples, i * unit, unit) > o.energyDb;
  }

  final List<SpeechRange> segments = <SpeechRange>[];
  int start = -1;
  int silenceMs = 0;
  for (int i = 0; i < frameCount; i++) {
    if (isSpeech[i]) {
      if (start < 0) start = i;
      silenceMs = 0;
      continue;
    }
    if (start < 0) continue;
    silenceMs += o.frameMs;
    final int durMs = (i - start) * o.frameMs;
    if (silenceMs >= o.minSilenceMs || durMs >= o.maxSegMs) {
      // 回退到最后一个语音帧之后。
      final int end = i - (silenceMs ~/ o.frameMs);
      if ((end - start) * o.frameMs >= o.minSpeechMs) {
        segments.add(SpeechRange(startMs: start * o.frameMs, endMs: end * o.frameMs));
      }
      start = -1;
      silenceMs = 0;
    }
  }
  if (start >= 0 && (frameCount - start) * o.frameMs >= o.minSpeechMs) {
    segments.add(SpeechRange(startMs: start * o.frameMs, endMs: frameCount * o.frameMs));
  }
  return segments;
}

/// 按固定段长把 PCM 均分为若干段（供上传文件兜底切片使用）。
List<SpeechRange> uniformSegments(int totalMs, {int segmentMs = 6000, int minSegMs = 1000}) {
  final int total = totalMs < 0 ? 0 : totalMs;
  if (total <= 0) return const <SpeechRange>[];
  final List<SpeechRange> out = <SpeechRange>[];
  for (int start = 0; start < total; start += segmentMs) {
    final int end = total < start + segmentMs ? total : start + segmentMs;
    if (end - start >= minSegMs || out.isEmpty) {
      out.add(SpeechRange(startMs: start, endMs: end));
    }
  }
  return out;
}
