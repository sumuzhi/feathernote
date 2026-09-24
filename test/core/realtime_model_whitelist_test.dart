/// P2 回归：实时模型名必须收敛到白名单（根因防护）。
///
/// 背景（真实缺陷）：`BAILIAN_REALTIME_MODEL` 被误写成
/// `qwen-audio-3.1-asr-flash-streaming` —— 但 3.1 只存在于 **filetrans（终稿）**
/// 线，实时（streaming/realtime）线**没有**该模型。服务端 `run-task` 被拒
/// → 帧全堆在待发队列 → 实时零句子 → 逐字稿为空。
///
/// 本文件固化 `resolveRealtimeModel()` 的契约：
/// 1. 白名单内 → 原样采用；
/// 2. 白名单外（如 3.1）→ 回退到默认值并标记 `fellBack`；
/// 3. 未配置（空串）→ 用默认值，但不算"回退"；
/// 4. 白名单本身的不变量（含默认值、不含 filetrans 型号）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/config/app_config.dart';

void main() {
  group('resolveRealtimeModel', () {
    test('白名单内：原样采用，不回退', () {
      for (final String model in <String>[
        'qwen-audio-3.0-asr-flash-streaming',
        'qwen3-asr-flash-realtime',
        'fun-asr-realtime',
        'paraformer-realtime-v2',
      ]) {
        final RealtimeModelResolution r = resolveRealtimeModel(model);
        expect(r.original, model);
        expect(r.effective, model, reason: '$model 在白名单内，应原样采用');
        expect(r.fellBack, isFalse, reason: '$model 不应触发回退');
      }
    });

    test('白名单外（3.1 实时误用）→ 回退到默认值并标记 fellBack', () {
      final RealtimeModelResolution r =
          resolveRealtimeModel('qwen-audio-3.1-asr-flash-streaming');
      expect(r.original, 'qwen-audio-3.1-asr-flash-streaming');
      expect(r.effective, kDefaultRealtimeModel, reason: '非法实时模型必须回退');
      expect(r.fellBack, isTrue);
      expect(kKnownRealtimeModels.contains(r.effective), isTrue,
          reason: '回退后的值必须落在白名单内');
    });

    test('任意未知模型名 → 回退（白名单是唯一出口）', () {
      for (final String bad in <String>[
        'gpt-4o-transcribe',
        'qwen-audio-3.1-asr-flash-filetrans', // filetrans 型号混入实时线
        'qwen3-asr-flash',
        'qwen-audio-3.0-asr-flash-streaming ', // 尾随空格 → trim 后合法
      ]) {
        final RealtimeModelResolution r = resolveRealtimeModel(bad);
        expect(kKnownRealtimeModels.contains(r.effective), isTrue,
            reason: 'effective 必须始终在白名单内（输入=$bad）');
      }
      // 尾随空格经 trim 后应命中白名单（视为合法，不回退）。
      final RealtimeModelResolution trimmed =
          resolveRealtimeModel('  qwen-audio-3.0-asr-flash-streaming  ');
      expect(trimmed.fellBack, isFalse);
      expect(trimmed.effective, 'qwen-audio-3.0-asr-flash-streaming');
    });

    test('未配置（空串 / null / 纯空格）→ 默认值，但不算回退', () {
      for (final String? empty in <String?>[null, '', '   ']) {
        final RealtimeModelResolution r = resolveRealtimeModel(empty);
        expect(r.effective, kDefaultRealtimeModel);
        expect(r.fellBack, isFalse, reason: '未配置不是"回退"，不应报错');
        expect(r.original, '');
      }
    });
  });

  group('白名单不变量', () {
    test('默认值必须本身在白名单内', () {
      expect(kKnownRealtimeModels.contains(kDefaultRealtimeModel), isTrue);
    });

    test('白名单不得含 filetrans（终稿）型号', () {
      for (final String model in kKnownRealtimeModels) {
        expect(model.contains('filetrans'), isFalse,
            reason: '实时白名单不应包含终稿型号：$model');
      }
      expect(
        kKnownRealtimeModels.contains('qwen-audio-3.1-asr-flash-filetrans'),
        isFalse,
      );
    });

    test('白名单不得含已证实不存在的 3.1 实时型号', () {
      expect(
        kKnownRealtimeModels.contains('qwen-audio-3.1-asr-flash-streaming'),
        isFalse,
      );
    });
  });
}
