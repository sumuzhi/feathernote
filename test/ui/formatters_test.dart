import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/utils/formatters.dart';

void main() {
  group('formatClock', () {
    test('分钟 + 秒（补零）', () {
      expect(formatClock(0), '0:00');
      expect(formatClock(754000), '12:34');
      expect(formatClock(59999), '0:59');
    });

    test('超过一小时带小时位', () {
      expect(formatClock(3753000), '1:02:33');
    });

    test('负数按 0 处理', () {
      expect(formatClock(-500), '0:00');
    });
  });

  group('formatDurationCn', () {
    test('分档文案', () {
      expect(formatDurationCn(30000), '低于 1 分钟');
      expect(formatDurationCn(32 * 60000), '32 分钟');
      expect(formatDurationCn(3 * 3600000), '3 小时');
      expect(formatDurationCn((3 * 60 + 12) * 60000), '3 小时 12 分钟');
    });
  });

  group('formatThousands', () {
    test('千分位', () {
      expect(formatThousands(0), '0');
      expect(formatThousands(999), '999');
      expect(formatThousands(1860), '1,860');
      expect(formatThousands(1234567), '1,234,567');
      expect(formatCharCount(1860), '1,860 字');
    });
  });

  group('日期与相对日', () {
    final DateTime now = DateTime(2026, 9, 24, 20, 0);

    test('今天 / 昨天 / 具体日期', () {
      expect(formatDayLabel(DateTime(2026, 9, 24, 9, 12), now: now), '今天');
      expect(formatDayLabel(DateTime(2026, 9, 23, 16, 40), now: now), '昨天');
      expect(formatDayLabel(DateTime(2026, 9, 18, 8, 0), now: now), '09-18');
    });

    test('时刻与日期时刻', () {
      expect(formatHm(DateTime(2026, 9, 24, 9, 5)), '09:05');
      expect(formatDayTime(DateTime(2026, 9, 24, 9, 12), now: now), '今天 09:12');
    });

    test('历史卡片元信息', () {
      expect(
        formatHistoryMeta(
          durationMs: 32 * 60000,
          createdAt: DateTime(2026, 9, 24, 9, 12),
          now: now,
        ),
        '32 分钟 · 今天 09:12',
      );
    });

    test('转写页信息行', () {
      expect(
        formatTranscriptInfo(durationMs: 32 * 60000, speakerCount: 3),
        '32 分钟 · 3 位说话人',
      );
    });
  });

  group('greetingFor', () {
    test('按时段', () {
      expect(greetingFor(DateTime(2026, 9, 24, 3)), '凌晨好');
      expect(greetingFor(DateTime(2026, 9, 24, 9)), '早上好');
      expect(greetingFor(DateTime(2026, 9, 24, 12)), '中午好');
      expect(greetingFor(DateTime(2026, 9, 24, 16)), '下午好');
      expect(greetingFor(DateTime(2026, 9, 24, 22)), '晚上好');
    });
  });
}
