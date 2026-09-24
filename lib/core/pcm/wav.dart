/// WAV（RIFF/WAVE，PCM 16bit）封装与时长解析（移植 `server/src/shared.js:477-509`）。
library;

import 'dart:typed_data';

/// 组装 WAV 文件字节（44B 头 + PCM）。
///
/// [pcm16le] 小端 16bit PCM；[sampleRate] 采样率；[channels] 声道数（默认 1）。
Uint8List buildWav({
  required Uint8List pcm16le,
  required int sampleRate,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final int dataBytes = pcm16le.length - (pcm16le.length % 2);
  final int bytesPerSample = bitsPerSample ~/ 8;
  final int byteRate = sampleRate * channels * bytesPerSample;
  final int blockAlign = channels * bytesPerSample;
  final int totalSize = 36 + dataBytes;

  final Uint8List out = Uint8List(44 + dataBytes);
  final ByteData view = ByteData.view(out.buffer, out.offsetInBytes);
  int offset = 0;

  void writeAscii(String text) {
    for (int i = 0; i < text.length; i++) {
      view.setUint8(offset++, text.codeUnitAt(i));
    }
  }

  // RIFF 头
  writeAscii('RIFF');
  view.setUint32(offset, totalSize, Endian.little);
  offset += 4;
  writeAscii('WAVE');
  // fmt 块
  writeAscii('fmt ');
  view.setUint32(offset, 16, Endian.little);
  offset += 4;
  view.setUint16(offset, 1, Endian.little); // PCM
  offset += 2;
  view.setUint16(offset, channels, Endian.little);
  offset += 2;
  view.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  view.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  view.setUint16(offset, blockAlign, Endian.little);
  offset += 2;
  view.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;
  // data 块
  writeAscii('data');
  view.setUint32(offset, dataBytes, Endian.little);
  offset += 4;
  out.setRange(44, 44 + dataBytes, pcm16le);
  return out;
}

/// 解析 WAV 头，得到**音频数据的真实时长**（毫秒）。
///
/// 对截断文件取实际可读字节数；解析失败（非 WAV / 缺 fmt / 缺 data / 头部截断）返回 `null`。
int? parseWavDurationMs(Uint8List wav) {
  if (wav.length < 44) return null;
  if (_ascii(wav, 0, 4) != 'RIFF' || _ascii(wav, 8, 12) != 'WAVE') return null;

  int offset = 12;
  ({int channels, int sampleRate, int bitsPerSample})? fmt;
  int dataLength = -1;
  while (offset + 8 <= wav.length) {
    final String chunkId = _ascii(wav, offset, offset + 4);
    final int chunkSize = _readUint32Le(wav, offset + 4);
    final int bodyStart = offset + 8;
    if (chunkId == 'fmt ' && bodyStart + 16 <= wav.length) {
      fmt = (
        channels: _readUint16Le(wav, bodyStart + 2) == 0 ? 1 : _readUint16Le(wav, bodyStart + 2),
        sampleRate: _readUint32Le(wav, bodyStart + 4),
        bitsPerSample: _readUint16Le(wav, bodyStart + 14),
      );
    } else if (chunkId == 'data') {
      final int readable = wav.length - bodyStart;
      dataLength = readable < 0 ? 0 : (chunkSize < readable ? chunkSize : readable);
    }
    // WAV 块按 2 字节对齐。
    offset = bodyStart + chunkSize + (chunkSize % 2);
  }
  if (fmt == null || dataLength < 0) return null;
  final int bytesPerSample = fmt.bitsPerSample ~/ 8;
  final int bytesPerSecond = fmt.sampleRate * fmt.channels * bytesPerSample;
  if (bytesPerSecond <= 0) return null;
  final int ms = ((dataLength / bytesPerSecond) * 1000).round();
  return ms > 0 ? ms : null;
}

/// 读取 ASCII 片段。
String _ascii(Uint8List bytes, int start, int end) {
  final StringBuffer buffer = StringBuffer();
  for (int i = start; i < end && i < bytes.length; i++) {
    buffer.writeCharCode(bytes[i]);
  }
  return buffer.toString();
}

/// 读取小端 uint32。
int _readUint32Le(Uint8List bytes, int offset) {
  return ByteData.view(bytes.buffer, bytes.offsetInBytes + offset, 4).getUint32(0, Endian.little);
}

/// 读取小端 uint16。
int _readUint16Le(Uint8List bytes, int offset) {
  return ByteData.view(bytes.buffer, bytes.offsetInBytes + offset, 2).getUint16(0, Endian.little);
}
