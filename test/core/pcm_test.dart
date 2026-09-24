import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/pcm/resampler.dart';
import 'package:smart_minutes_flutter/core/pcm/wav.dart';

/// 构造指定样本数的静音 PCM（16bit 小端）。
Uint8List _silence(int samples) => Uint8List(samples * 2);

void main() {
  group('buildWav', () {
    test('44B 头 + PCM 数据，RIFF/WAVE/data 标识正确', () {
      // 1 秒：16kHz × 单声道 × 16bit = 32000 字节
      final Uint8List pcm = _silence(16000);
      final Uint8List wav = buildWav(pcm16le: pcm, sampleRate: 16000);

      expect(wav.length, 44 + 32000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      final ByteData view = ByteData.view(wav.buffer, wav.offsetInBytes);
      // data chunk 长度字段
      expect(view.getUint32(40, Endian.little), 32000);
      // fmt chunk：声道数(22) / 采样率(24) / 位深(34)
      expect(view.getUint16(22, Endian.little), 1);
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint16(34, Endian.little), 16);
    });

    test('奇数长度 PCM 被截断到偶数（丢弃半个样本）', () {
      final Uint8List wav = buildWav(pcm16le: Uint8List(101), sampleRate: 16000);
      expect(wav.length, 44 + 100);
    });

    test('立体声字节率与块对齐按声道数计算', () {
      final Uint8List wav = buildWav(
        pcm16le: _silence(16000 * 2),
        sampleRate: 16000,
        channels: 2,
      );
      final ByteData view = ByteData.view(wav.buffer, wav.offsetInBytes);
      expect(view.getUint16(22, Endian.little), 2);
      // byteRate = 16000 × 2 × 2 = 64000
      expect(view.getUint32(28, Endian.little), 64000);
      // blockAlign = 2 × 2 = 4
      expect(view.getUint16(32, Endian.little), 4);
    });
  });

  group('parseWavDurationMs', () {
    test('1 秒 16kHz 单声道解析为 1000ms', () {
      final Uint8List wav = buildWav(pcm16le: _silence(16000), sampleRate: 16000);
      expect(parseWavDurationMs(wav), 1000);
    });

    test('2 秒 16kHz 立体声解析为 2000ms', () {
      final Uint8List wav = buildWav(
        pcm16le: _silence(16000 * 2 * 2),
        sampleRate: 16000,
        channels: 2,
      );
      expect(parseWavDurationMs(wav), 2000);
    });

    test('非 WAV 输入返回 null', () {
      expect(parseWavDurationMs(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    });
  });

  group('Resampler', () {
    test('同采样率：needed 为 false 且原样返回同一实例', () {
      final Uint8List pcm = _silence(160);
      final Resampler resampler = Resampler(fromHz: 16000, toHz: 16000);
      expect(resampler.needed, isFalse);
      expect(resampler.convert(pcm), same(pcm));
    });

    test('48kHz → 16kHz 下采样为 1/3', () {
      final Uint8List out = Resampler(fromHz: 48000, toHz: 16000).convert(_silence(4800));
      expect(out.length, 1600 * 2);
    });

    test('8kHz → 16kHz 上采样为 2 倍', () {
      final Uint8List out = Resampler(fromHz: 8000, toHz: 16000).convert(_silence(800));
      expect(out.length, 1600 * 2);
    });

    test('空输入与不足一个样本时返回空，不抛错', () {
      expect(Resampler(fromHz: 48000, toHz: 16000).convert(Uint8List(0)).length, 0);
      expect(Resampler(fromHz: 48000, toHz: 16000).convert(Uint8List(1)).length, 0);
    });
  });
}
