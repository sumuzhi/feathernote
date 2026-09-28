/// `friendlyFinalizeError` 映射回归：原始错误串（error.toString()）→ 用户可读文案。
///
/// 关键约束：任何输入都**不得**把英文异常名 / 错误码 / 堆栈透传给用户。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/error/finalize_error_text.dart';

void main() {
  test('无有效语音（模拟器空录的已知形态）', () {
    final String text = friendlyFinalizeError(
      'Bad state: ASR_RESPONSE_HAVE_NO_WORDS',
    );
    expect(text, contains('没有识别到说话内容'));
    expect(text.contains('ASR'), isFalse, reason: '不得透传原始错误码');
  });

  test('文件超限', () {
    expect(
      friendlyFinalizeError(
        'AppError(engineError E_TOO_LARGE): 文件过大：130.0MB 超过上限 128MB',
      ),
      contains('文件过大'),
    );
  });

  test('任务超时', () {
    expect(
      friendlyFinalizeError(
        'AppError(engineError E_TIMEOUT): filetrans 未成功（status=timeout）',
      ),
      contains('超时'),
    );
  });

  test('鉴权失败（401 / Key 无效）', () {
    expect(
      friendlyFinalizeError('AppError(unauthorized): Requested resource requires authentication (401)'),
      contains('鉴权'),
    );
  });

  test('网络异常', () {
    expect(
      friendlyFinalizeError('SocketException: Connection failed (ENETUNREACH)'),
      contains('网络'),
    );
  });

  test('限流', () {
    expect(
      friendlyFinalizeError('AppError(engineError E_RATE_LIMIT): Throttling (429)'),
      contains('繁忙'),
    );
  });

  test('filetrans 任务失败（非超时）', () {
    expect(
      friendlyFinalizeError('AppError(engineError E_TASK_FAILED): filetrans 未成功（status=failed）'),
      contains('处理失败'),
    );
  });

  test('归档缺失', () {
    expect(friendlyFinalizeError('AppError(internal): 会议不存在，无法重试'), contains('录音文件缺失'));
  });

  test('兜底：未知错误不得透传原始串', () {
    const String raw = 'Expection: something_weird_0xdeadbeef@stack#frame';
    final String text = friendlyFinalizeError(raw);
    expect(text.contains('something_weird'), isFalse);
    expect(text, contains('转写失败'));
  });

  test('空 / null 输入', () {
    expect(friendlyFinalizeError(null), isNotEmpty);
    expect(friendlyFinalizeError(''), isNotEmpty);
  });
}
