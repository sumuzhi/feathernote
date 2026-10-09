/// `importItemView` 描述优先级回归（修复 ④）。
///
/// 历史「最近导入」列表第二行描述应遵循：
/// **AI 纪要预览（`minutesExcerpt`）> 失败提示 > 处理中占位 > 通用占位**，
/// 与详情页一致（此前写死「来自视频 / 音频导入」导致不一致）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/ui/pages/import_page.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';

/// 构造导入会议摘要投影。
MeetingSummary _summary({
  required ImportStatus importStatus,
  String minutesExcerpt = '',
  bool hasMinutes = false,
}) {
  return MeetingSummary(
    id: 'm1',
    title: '会议',
    createdAt: DateTime(2026, 1, 1, 9, 12),
    durationMs: 60000,
    speakerCount: 1,
    status: MeetingStatus.minutesReady,
    finalizeStatus: FinalizeStatus.done,
    hasMinutes: hasMinutes,
    minutesPartial: false,
    source: MeetingSource.imported,
    importStatus: importStatus,
    minutesExcerpt: minutesExcerpt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('已生成纪要 → 优先展示真实预览（与详情页一致）', () {
    final HistoryItemView v = importItemView(
      _summary(
        importStatus: ImportStatus.done,
        minutesExcerpt: '这是纪要首行预览文本',
        hasMinutes: true,
      ),
      DateTime.now(),
    );
    expect(v.description, '这是纪要首行预览文本');
    expect(v.badge, HistoryBadge.imported);
    expect(v.processing, isFalse);
  });

  test('done 但无纪要 → 通用占位（而非写死「来自视频/音频导入」的误匹配）', () {
    final HistoryItemView v = importItemView(
      _summary(importStatus: ImportStatus.done, minutesExcerpt: '', hasMinutes: false),
      DateTime.now(),
    );
    expect(v.description, '来自视频 / 音频导入');
    expect(v.processing, isFalse);
  });

  test('失败 → 失败提示 + importFailed badge + 非处理中', () {
    final HistoryItemView v = importItemView(
      _summary(importStatus: ImportStatus.failed, minutesExcerpt: ''),
      DateTime.now(),
    );
    expect(v.description, '导入失败，可进入详情页重试');
    expect(v.badge, HistoryBadge.importFailed);
    expect(v.processing, isFalse);
  });

  test('处理中（transcribing）→ 处理中占位 + processing 角标', () {
    final HistoryItemView v = importItemView(
      _summary(importStatus: ImportStatus.transcribing, minutesExcerpt: ''),
      DateTime.now(),
    );
    expect(v.description, '导入处理中，完成后自动生成纪要');
    expect(v.processing, isTrue);
    expect(v.badge, HistoryBadge.imported);
  });

  test('导入完成态不显示 processing 角标', () {
    final HistoryItemView v = importItemView(
      _summary(importStatus: ImportStatus.done, minutesExcerpt: '纪要', hasMinutes: true),
      DateTime.now(),
    );
    expect(v.processing, isFalse);
  });
}
