/// 数据备份构建器单测：纯函数（JSON / Markdown / 流式 / 本地 ZIP）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  group('writeBackupJsonStreaming（流式写，卡死修复）', () {
    test('流式输出解码后与 buildBackupJson 全量编码完全等价', () async {
      final List<Meeting> meetings = <Meeting>[
        _meeting('m1', minutesMd: '# 核心观点\n- 结论 A', segmentCount: 3),
        _meeting('m2', minutesMd: null, segmentCount: 1),
      ];
      final Map<String, dynamic> expected = buildBackupJson(
        meetings: meetings,
        schemaVersion: 7,
        exportedAt: exportedAt,
      );

      final File tmp = File(p.join(
        Directory.systemTemp.path,
        'bk_json_${math.Random().nextInt(1 << 30)}.json',
      ));
      await tmp.create(recursive: true);
      await writeBackupJsonStreaming(
        tmp.path,
        expected,
        (_, _) {},
        () => false,
      );

      final Map<String, dynamic> actual =
          jsonDecode(await tmp.readAsString()) as Map<String, dynamic>;
      // 解码后逐字段相等（排版差异被忽略）。
      expect(actual, expected);
      await tmp.delete();
    });

    test('取消信号：首场即中止，不产出完整文件', () async {
      final Map<String, dynamic> root = buildBackupJson(
        meetings: <Meeting>[_meeting('m1'), _meeting('m2')],
        exportedAt: exportedAt,
      );
      final File tmp = File(p.join(
        Directory.systemTemp.path,
        'bk_json_cancel_${math.Random().nextInt(1 << 30)}.json',
      ));
      await tmp.create(recursive: true);
      bool threw = false;
      try {
        await writeBackupJsonStreaming(
          tmp.path,
          root,
          (_, _) {},
          () => true, // 立即取消
        );
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
      // 文件可能留了半截头部，但绝不包含第二个会议（取消在首场前触发）。
      final String content = await tmp.readAsString();
      expect(content, isNot(contains('"id": "m2"')));
      await tmp.delete();
    });
  });

  group('meetingMapToMarkdown（isolate 内重建，与 buildMeetingMarkdown 一致）', () {
    test('含纪要会议：输出逐字符等于 buildMeetingMarkdown', () {
      final Meeting m = _meeting('m1', minutesMd: '## 核心观点\n- 结论 A');
      final Map<String, dynamic> mMap =
          (buildBackupJson(meetings: <Meeting>[m], exportedAt: exportedAt)
              ['meetings'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(meetingMapToMarkdown(mMap), buildMeetingMarkdown(m));
    });

    test('无纪要会议：输出逐字符等于 buildMeetingMarkdown', () {
      final Meeting m = _meeting('m2', minutesMd: null);
      final Map<String, dynamic> mMap =
          (buildBackupJson(meetings: <Meeting>[m], exportedAt: exportedAt)
              ['meetings'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(meetingMapToMarkdown(mMap), buildMeetingMarkdown(m));
    });
  });

  group('buildLocalBackupZip（本地 ZIP 构建，无插件）', () {
    test('产出合规 ZIP：backup.json 等价 + 每场一个 md + 进度递增', () async {
      final List<Meeting> meetings = <Meeting>[
        _meeting('m1', minutesMd: '# 核心观点\n- 结论 A', segmentCount: 2),
        _meeting('m2', minutesMd: null, segmentCount: 1),
      ];
      final Map<String, dynamic> backupMap = buildBackupJson(
        meetings: meetings,
        schemaVersion: 7,
        exportedAt: exportedAt,
      );

      final Directory workDir = Directory(p.join(
        Directory.systemTemp.path,
        'bk_zip_${math.Random().nextInt(1 << 30)}',
      ));
      final String zipPath = p.join(workDir.path, 'out.zip');
      final List<double> fractions = <double>[];
      await buildLocalBackupZip(
        backupMap: backupMap,
        audioPaths: const <String?>[null, null],
        workDirPath: workDir.path,
        zipPath: zipPath,
        onProgress: (double f, _) => fractions.add(f),
        isCancelled: () => false,
      );

      // ZIP 存在且可解。
      expect(File(zipPath).existsSync(), isTrue);
      final Archive archive =
          ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
      final Map<String, ArchiveFile> byName = <String, ArchiveFile>{
        for (final ArchiveFile f in archive.files) f.name: f,
      };
      expect(byName.containsKey('backup.json'), isTrue);
      final Map<String, dynamic> actualJson = jsonDecode(
        const Utf8Decoder().convert(byName['backup.json']!.content as List<int>),
      ) as Map<String, dynamic>;
      expect(actualJson, backupMap);

      // 每场会议一个 md（文件名含标题，这里只校验数量与扩展名）。
      final List<String> mdNames = byName.keys
          .where((String n) => n.startsWith('minutes/') && n.endsWith('.md'))
          .toList();
      expect(mdNames.length, 2);

      // 进度从 0 单调递增到 1.0（无音频时最后一步 audioCount=1，done=0→0.5）。
      expect(fractions, isNotEmpty);
      for (int i = 1; i < fractions.length; i++) {
        expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]));
      }

      await workDir.delete(recursive: true);
    });

    test('取消：ZIP 不会被创建（及时中止 + 释放资源）', () async {
      final Map<String, dynamic> backupMap = buildBackupJson(
        meetings: <Meeting>[_meeting('m1'), _meeting('m2')],
        exportedAt: exportedAt,
      );
      final Directory workDir = Directory(p.join(
        Directory.systemTemp.path,
        'bk_zip_cancel_${math.Random().nextInt(1 << 30)}',
      ));
      final String zipPath = p.join(workDir.path, 'out.zip');
      bool threw = false;
      try {
        await buildLocalBackupZip(
          backupMap: backupMap,
          audioPaths: const <String?>[null, null],
          workDirPath: workDir.path,
          zipPath: zipPath,
          onProgress: (_, _) {},
          isCancelled: () => true, // 立即取消
        );
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
      expect(File(zipPath).existsSync(), isFalse);
      if (workDir.existsSync()) await workDir.delete(recursive: true);
    });
  });
}
