/// 音频帧编解码（1:1 移植 `server/src/shared.js:342-391`）。
///
/// 帧格式：`flag(1B) seq(4B LE) start_ms(4B LE) pcm(...)`，头部 9B；
/// 20ms/帧 = 320 样本 = 640B PCM（16kHz / 16bit / 单声道）。
library;

import 'dart:typed_data';

/// 单帧时长（毫秒）。
const int frameMs = 20;

/// 单帧样本数（16000Hz × 20ms）。
const int frameSamples = 320;

/// 单帧 PCM 字节数。
const int frameBytes = frameSamples * 2;

/// 二进制帧固定头部长度。
const int frameHeaderBytes = 9;

/// 音频帧。
class AudioFrame {
  /// 构造音频帧。
  const AudioFrame({required this.flag, required this.seq, required this.startMs, required this.pcm});

  /// 标志位（1 字节，默认 0）。
  final int flag;

  /// 帧序号（无符号 32 位）。
  final int seq;

  /// 帧起始毫秒（无符号 32 位）。
  final int startMs;

  /// PCM 负载（小端 int16，长度应为偶数）。
  final Uint8List pcm;

  /// 帧结束毫秒（含）。
  int get endMs => startMs + frameMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioFrame &&
          other.flag == flag &&
          other.seq == seq &&
          other.startMs == startMs &&
          _bytesEqual(other.pcm, pcm);

  @override
  int get hashCode => Object.hash(flag, seq, startMs, Object.hashAll(pcm));

  @override
  String toString() => 'AudioFrame(seq=$seq, startMs=${startMs}ms, pcm=${pcm.length}B)';
}

/// 逐字节比较。
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  final Uint8List other = b;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != other[i]) return false;
  }
  return true;
}

/// 编码音频帧为二进制（小端）。
Uint8List encodeAudioFrame(AudioFrame frame) {
  final Uint8List pcm = frame.pcm;
  final Uint8List out = Uint8List(frameHeaderBytes + pcm.length);
  final ByteData view = ByteData.view(out.buffer, out.offsetInBytes);
  view.setUint8(0, frame.flag & 0xff);
  view.setUint32(1, frame.seq & 0xffffffff, Endian.little);
  view.setUint32(5, frame.startMs & 0xffffffff, Endian.little);
  out.setRange(frameHeaderBytes, out.length, pcm);
  return out;
}

/// 解码二进制音频帧；长度不足头部时返回 `null`（由调用方报 `E_AUDIO`）。
AudioFrame? decodeAudioFrame(Uint8List raw) {
  if (raw.length < frameHeaderBytes) return null;
  final ByteData view = ByteData.view(raw.buffer, raw.offsetInBytes, raw.length);
  final int flag = view.getUint8(0);
  final int seq = view.getUint32(1, Endian.little);
  final int startMs = view.getUint32(5, Endian.little);
  final Uint8List pcm = Uint8List.sublistView(raw, frameHeaderBytes);
  return AudioFrame(flag: flag, seq: seq, startMs: startMs, pcm: pcm);
}

/// PCM 字节（小端 16bit）转 `Int16List`；奇数长度截掉尾字节。
Int16List bytesToInt16(Uint8List bytes) {
  final Uint8List src = bytes;
  final int usable = src.length - (src.length % 2);
  final Int16List out = Int16List(usable ~/ 2);
  final ByteData view = ByteData.view(src.buffer, src.offsetInBytes, src.length);
  for (int i = 0; i < out.length; i++) {
    out[i] = view.getInt16(i * 2, Endian.little);
  }
  return out;
}

/// `Int16List` 转小端 PCM 字节。
Uint8List int16ToBytes(Int16List samples) {
  final Uint8List out = Uint8List(samples.length * 2);
  final ByteData view = ByteData.view(out.buffer, out.offsetInBytes);
  for (int i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}
