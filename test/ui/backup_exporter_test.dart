/// 数据备份构建器单测（纯函数：JSON / Markdown；不含 IO 落盘）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/utils/backup_exporter.dart';

Meeting _meeting(String id, {String? minutesMd, int segmentCount = 2}) =>
    Meeting(
      id: id,
      title: '会议 $id',
      createdAt: DateTime(2026, 10, 9, 10),
      durationMs: 60000,
      sampleRate: 16000,
      speakerCount: 2,
      status: MeetingStatus.minutesReady,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.done,
      transcriptSource: TranscriptSource.filetrans,
      audioStatus: AudioStatus.done,
      audioBytes: 1024,
      audioKey: id,
      minutesPartial: false,
      minutesMd: minutesMd,
      segments: <TranscriptSegment>[
        for (int i = 0; i < segmentCount; i++)
          TranscriptSegment(
            meetingId: id,
            segmentId: 'seg_${id}_$i',
            ordinal: i,
            speakerId: 'spk_1',
            speakerName: '说话人 1',
            text: '第 $i 段内容',
            startTime: i * 1000,
            endTime: i * 1000 + 800,
            confidence: 0.9,
            seqStart: i,
            seqEnd: i,
          ),
      ],
      speakers: <Speaker>[
        Speaker(
          meetingId: id,
          speakerId: 'spk_1',
          name: '说话人 1',
          colorIndex: 0,
          firstSeenMs: 0,
        ),
      ],
    );

void main() {
  final DateTime exportedAt = DateTime(2026, 10, 9, 20);

  group('buildBackupJson', () {
    test('包含全量会议字段：元信息 + 逐字稿 + AI 纪要 + 说话人', () {
      final Map<String, dynamic> json = buildBackupJson(
        meetings: <Meeting>[
          _meeting('m1', minutesMd: '# 核心观点\n- 结论 A'),
          _meeting('m2', minutesMd: null),
        ],
        schemaVersion: 3,
        exportedAt: exportedAt,
      );
      expect(json['app'], 'feathernote');
      expect(json['kind'], 'backup');
      expect(json['schemaVersion'], 3);
      expect(json['exportedAt'], exportedAt.toIso8601String());
      expect(json['count'], 2);

      final List<dynamic> meetings = json['meetings'] as List<dynamic>;
      expect(meetings.length, 2);
      final Map<String, dynamic> m1 =
          meetings.first as Map<String, dynamic>;
      expect(m1['id'], 'm1');
      expect(m1['title'], '会议 m1');
      expect(m1['minutesMd'], '# 核心观点\n- 结论 A');
      expect(m1['status'], 'minutes_ready');
      expect(m1['audioKey'], 'm1');
      final List<dynamic> segments = m1['segments'] as List<dynamic>;
      expect(segments.length, 2);
      expect((segments.first as Map<String, dynamic>)['text'], '第 0 段内容');
      final List<dynamic> speakers = m1['speakers'] as List<dynamic>;
      expect(speakers.length, 1);
      expect((speakers.first as Map<String, dynamic>)['name'], '说话人 1');
    });

    test('空库：count=0、meetings 空数组', () {
      final Map<String, dynamic> json = buildBackupJson(
        meetings: const <Meeting>[],
        exportedAt: exportedAt,
      );
      expect(json['count'], 0);
      expect(json['meetings'], isEmpty);
    });
  });

  group('buildMeetingMarkdown（每场会议单独一个 md）', () {
    test('包含标题 + 元信息 + AI 纪要 + 逐字稿', () {
      final String md = buildMeetingMarkdown(
        _meeting('m1', minutesMd: '## 核心观点\n- 结论 A'),
      );
      expect(md, contains('# 会议 m1'));
      expect(md, contains('- 创建时间：2026-10-09T10:00:00.000'));
      expect(md, contains('## AI 纪要'));
      expect(md, contains('- 结论 A'));
      expect(md, contains('## 逐字稿（2 段）'));
      expect(md, contains('第 1 段内容'));
    });

    test('无纪要会议：跳过 AI 纪要小节，不产生空标题', () {
      final String md = buildMeetingMarkdown(
        _meeting('m2', minutesMd: null),
      );
      expect(md, contains('# 会议 m2'));
      expect(md, isNot(contains('## AI 纪要')));
    });
  });
}
