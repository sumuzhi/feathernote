/// P0-1 单元：WAV **流式补头**工具的正确性。
///
/// - [buildWavHeader] 只产 44 字节头，其声明的 `data` 大小 == 传入 `pcmBytes`；
/// - 头 + 原始 PCM 拼起来应与 [buildWav] 的整份产物**逐字节一致**（保证流式补头
///   与历史上的整体拼装在语义上等价）；
/// - [wavDurationMsFromPcmBytes] 与 [parseWavDurationMs] 结果一致。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/pcm/wav.dart';

Uint8List _pcm(int bytes) {
  final Uint8List out = Uint8List(bytes);
  for (int i = 0; i < bytes; i++) {
    out[i] = i % 256;
  }
  return out;
}

void main() {
  test('buildWavHeader: 44B 头，data 大小 == pcmBytes，RIFF/WAVE 正确', () {
    final Uint8List header = buildWavHeader(pcmBytes: 3200, sampleRate: 16000);
    expect(header.length, kWavHeaderBytes);
    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(header.sublist(36, 40)), 'data');
    // data 大小字段（偏移 40，小端 uint32）。
    final ByteData view = ByteData.view(header.buffer, header.offsetInBytes);
    expect(view.getUint32(40, Endian.little), 3200);
    // RIFF size 字段（偏移 4）= 36 + dataBytes。
    expect(view.getUint32(4, Endian.little), 36 + 3200);
  });

  test('流式「头 + PCM」与 buildWav 整份产物逐字节一致', () {
    final Uint8List pcm = _pcm(1280); // 20ms×2 = 40ms @16k/16bit/mono
    final Uint8List whole = buildWav(pcm16le: pcm, sampleRate: 16000);
    final Uint8List streamed = Uint8List(kWavHeaderBytes + pcm.length)
      ..setRange(0, kWavHeaderBytes, buildWavHeader(pcmBytes: pcm.length, sampleRate: 16000))
      ..setRange(kWavHeaderBytes, kWavHeaderBytes + pcm.length, pcm);
    expect(streamed.length, whole.length);
    for (int i = 0; i < whole.length; i++) {
      if (streamed[i] != whole[i]) {
        fail('字节不一致 @ $i：streamed=${streamed[i]} whole=${whole[i]}');
      }
    }
  });

  test('wavDurationMsFromPcmBytes 与 parseWavDurationMs 一致', () {
    for (final int bytes in <int>[640, 3200, 16000, 32000]) {
      final Uint8List wav = buildWav(pcm16le: _pcm(bytes), sampleRate: 16000);
      expect(
        parseWavDurationMs(wav),
        wavDurationMsFromPcmBytes(bytes, sampleRate: 16000),
        reason: 'bytes=$bytes',
      );
    }
    expect(wavDurationMsFromPcmBytes(32000, sampleRate: 16000), 1000);
  });
}
