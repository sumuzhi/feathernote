/// A0/A4 回归：日志环形缓冲与脱敏。
///
/// 1. 环形缓冲：**不受日志级别过滤影响**（`LOG_LEVEL=info` 时 debug 也应入缓冲），
///    并受容量上限约束；
/// 2. 脱敏：任何日志都**不得打印完整 API Key**（只留前 4 位 + 长度），
///    WS / HTTP 的 `Authorization` 必须打码。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/log/log.dart';

void main() {
  setUp(clearLogHistory);

  test('环形缓冲：debug 也入缓冲，且不超过容量上限', () {
    setLogLevel('info'); // 控制台只放 info，但缓冲仍应收全量。
    logInfo('test', '信息一');
    logDebug('test', '调试一');

    expect(recentLogs(), hasLength(2), reason: 'debug 也必须进缓冲，供导出诊断');
    expect(recentLogs().last, contains('调试一'));

    for (int i = 0; i < kLogHistoryCapacity + 50; i++) {
      logInfo('test', '批量 $i');
    }
    expect(logHistoryLength, kLogHistoryCapacity, reason: '缓冲必须封顶，不能无限增长');
    expect(recentLogs(limit: 1).single, contains('批量 ${kLogHistoryCapacity + 49}'));
  });

  test('maskSecret：只保留前 4 位与长度', () {
    expect(maskSecret('sk-1234567890abcdef'), 'sk-1****(len=19)');
    expect(maskSecret('abc'), '****(len=3)');
    expect(maskSecret(''), '(empty)');
    expect(maskSecret(null), '(empty)');
    // 关键：输出绝不能包含完整密钥。
    expect(maskSecret('sk-1234567890abcdef'), isNot(contains('1234567890abcdef')));
  });

  test('redactHeaders：Authorization / Signature 打码，普通头保留', () {
    final Map<String, Object?> redacted = redactHeaders(<String, String>{
      'Authorization': 'Bearer sk-1234567890abcdef',
      'X-DashScope-WorkSpace': 'ws-1',
      'Content-Type': 'application/json',
    });

    expect('${redacted['Authorization']}', contains('Bearer '));
    expect('${redacted['Authorization']}', contains('len=19'));
    expect('${redacted['Authorization']}', isNot(contains('1234567890abcdef')));
    expect(redacted['X-DashScope-WorkSpace'], 'ws-1');
    expect(redacted['Content-Type'], 'application/json');
  });

  test('dumpLogs：导出文本按时间升序拼接', () {
    logInfo('recorder', '第一条');
    logInfo('transcription', '第二条');
    final String dump = dumpLogs();
    expect(dump.indexOf('第一条') < dump.indexOf('第二条'), isTrue);
  });
}
