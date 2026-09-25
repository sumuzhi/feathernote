/// [measurePcm] / [PcmLevel] 契约：判断「麦克风到底有没有采到声音」。
///
/// 取值锚点来自一次真实事故样本（设备上归档 WAV 的实测能量）：
/// - 真实语音：peak 1944 – 6255（rms 181 – 667）；
/// - `AudioRecord` 哑掉后的数字静音：peak = 2（±2 LSB 底噪）。
/// 阈值 [kSilencePeakThreshold] = 150 与两边都留约一个数量级余量，本测试固化这一点。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/pcm/level_meter.dart';

/// 造一段 PCM16LE：每个采样取 [value]（可为负）。
Uint8List _pcm(List<int> values) {
  final Uint8List bytes = Uint8List(values.length * 2);
  final ByteData view = ByteData.view(bytes.buffer);
  for (int i = 0; i < values.length; i++) {
    view.setInt16(i * 2, values[i], Endian.little);
  }
  return bytes;
}

void main() {
  group('measurePcm 基本读数', () {
    test('全零 PCM → 静音', () {
      final PcmLevel level = measurePcm(Uint8List(640));
      expect(level.peak, 0);
      expect(level.rms, 0);
      expect(level.isSilent, isTrue);
    });

    test('真实语音量级（peak≈5000）→ 非静音', () {
      final PcmLevel level = measurePcm(_pcm(<int>[0, 100, -5000, 3000, 120]));
      expect(level.peak, 5000, reason: 'peak 取绝对值最大值');
      expect(level.isSilent, isFalse);
      expect(level.rms, greaterThan(0));
    });

    test('底噪级（peak=2，事故样本复刻）→ 静音', () {
      final PcmLevel level = measurePcm(_pcm(<int>[2, 2, -2, -2, -2, -2, -2, -2]));
      expect(level.peak, 2);
      expect(level.isSilent, isTrue, reason: '±2 LSB 是数字静音，不是语音');
    });

    test('阈值两侧各留一个数量级余量', () {
      expect(
        measurePcm(_pcm(<int>[kSilencePeakThreshold - 1])).isSilent,
        isTrue,
        reason: '阈值下方判静音',
      );
      expect(
        measurePcm(_pcm(<int>[kSilencePeakThreshold])).isSilent,
        isFalse,
        reason: '阈值本身算有信号',
      );
      // 与实测样本对照：真实语音峰值（1944）远高于阈值，静音峰值（2）远低于阈值。
      expect(kSilencePeakThreshold, lessThan(1944 ~/ 10));
      expect(kSilencePeakThreshold, greaterThan(2 * 10));
    });
  });

  group('measurePcm 畸形输入安全', () {
    test('空数组 / 1 字节 / 奇数长度都不抛异常且判静音', () {
      expect(measurePcm(Uint8List(0)).isSilent, isTrue);
      expect(measurePcm(Uint8List(1)).isSilent, isTrue);
      expect(measurePcm(Uint8List(3)).isSilent, isTrue);
      expect(measurePcm(Uint8List(639)).peak, greaterThanOrEqualTo(0));
    });

    test('奇数长度：末尾残余字节被忽略', () {
      // [1000, 500] + 1 个残余字节 → 只解析前 4 字节。
      final Uint8List bytes = Uint8List(5);
      final ByteData view = ByteData.view(bytes.buffer);
      view.setInt16(0, 1000, Endian.little);
      view.setInt16(2, 500, Endian.little);
      expect(measurePcm(bytes).peak, 1000);
    });

    test('非零 offsetInBytes 的视图也能正确解析', () {
      final Uint8List big = Uint8List(16);
      final ByteData bigView = ByteData.view(big.buffer);
      for (int i = 0; i < 8; i++) {
        bigView.setInt16(i * 2, i == 5 ? 9000 : 1, Endian.little);
      }
      final Uint8List slice = Uint8List.sublistView(big, 4, 12); // 含 index 2..5
      expect(measurePcm(slice).peak, 9000, reason: '必须按 buffer 实际偏移解析');
    });
  });

  group('PcmLevel.silent', () {
    test('常量读数', () {
      const PcmLevel level = PcmLevel.silent();
      expect(level.peak, 0);
      expect(level.rms, 0);
      expect(level.isSilent, isTrue);
    });
  });
}
