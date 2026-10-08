/// schema v1 → v2 迁移测试（IMPORT-PIPELINE-DESIGN §5.2 / §8 T1 验收）。
///
/// 硬性门禁：**用真实 v1 存量库升级**（临时目录造旧库 → 打开 → drift onUpgrade
/// → 断言旧数据全量可读 + 子表存活 + 新列可用 + `source='imported'` 过 CHECK）。
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/backend/storage/app_database.dart';
import 'package:smart_minutes_flutter/backend/storage/meeting_repository.dart';
import 'package:smart_minutes_flutter/backend/storage/schema.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmpDir;
  late String dbPath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('sm_migration_test');
    dbPath = '${tmpDir.path}/minutes_v1.db';
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  /// 用 v1 DDL 在临时目录搭一个真实的 v1 存量库：
  /// 1 场录音会议（microphone，含纪要）+ 2 段逐字稿 + 1 个说话人 + 1 条终稿原始 JSON。
  void buildV1Database() {
    final Database raw = sqlite3.open(dbPath);
    try {
      raw.execute('PRAGMA foreign_keys = ON');
      for (final String statement in kSchemaStatements) {
        // v1 建表：meetings 用 v1 版本（无 import_* 列、source CHECK 不含 imported）。
        if (statement.startsWith('CREATE TABLE IF NOT EXISTS meetings')) {
          raw.execute(kV1MeetingsStatements.first);
        } else {
          raw.execute(statement);
        }
      }
      raw.execute(
        "INSERT INTO schema_meta(key, value) VALUES('$kSchemaMetaVersionKey', '1')",
      );
      raw.execute('PRAGMA user_version = 1');

      // 存量数据：一场已完成纪要的录音会议（参数绑定插入，避免引号转义）。
      final PreparedStatement insertMeeting = raw.prepare(
        'INSERT INTO meetings (id, title, created_at, duration_ms, sample_rate, '
        'speaker_count, minutes_md, minutes_partial, minutes_error, status, source, '
        'finalize_status, transcript_source, finalize_error, audio_status, audio_key, '
        'audio_error, audio_bytes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      insertMeeting.execute(<Object?>[
        'mtg_v1_old', 'v1 存量会议', '2026-09-01T02:00:00.000Z', 62000, 16000, 2,
        '# v1 纪要', 0, null, 'minutes_ready', 'microphone', 'done', 'filetrans',
        null, 'done', 'mtg_v1_old', null, 1996800,
      ]);
      insertMeeting.close();

      final PreparedStatement insertSegments = raw.prepare(
        'INSERT INTO transcript_segments (meeting_id, segment_id, ordinal, speaker_id, '
        'speaker_name, text, start_time, end_time, confidence, seq_start, seq_end) VALUES '
        '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      insertSegments.execute(<Object?>[
        'mtg_v1_old', 'seg_1', 0, 'spk_1', '说话人 1', '旧库第一句', 0, 3000, 0.9, 0, 29,
        'mtg_v1_old', 'seg_2', 1, 'spk_2', '说话人 2', '旧库第二句', 3000, 6000, 0.9, 30, 59,
      ]);
      insertSegments.close();

      final PreparedStatement insertSpeakers = raw.prepare(
        'INSERT INTO speakers (meeting_id, speaker_id, name, color_index, first_seen_ms) '
        'VALUES (?, ?, ?, ?, ?), (?, ?, ?, ?, ?)',
      );
      insertSpeakers.execute(<Object?>[
        'mtg_v1_old', 'spk_1', '说话人 1', 0, 0,
        'mtg_v1_old', 'spk_2', '说话人 2', 1, 3000,
      ]);
      insertSpeakers.close();

      final PreparedStatement insertRaw = raw.prepare(
        'INSERT INTO filetrans_raw (meeting_id, json, created_at) VALUES (?, ?, ?)',
      );
      insertRaw.execute(<Object?>[
        'mtg_v1_old', '{"raw":true}', '2026-09-01T02:10:00.000Z',
      ]);
      insertRaw.close();
    } finally {
      raw.close();
    }
  }

  group('schema v1 → v2 迁移（真实 v1 存量库）', () {
    test('旧会议全量可读（含子表），新列默认值正确', () async {
      buildV1Database();
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final DriftMeetingRepository repo = DriftMeetingRepository(db);
      final Meeting? meeting = await repo.loadMeeting('mtg_v1_old');

      // 旧会议主体字段逐项可读。
      expect(meeting, isNotNull);
      expect(meeting!.title, 'v1 存量会议');
      expect(meeting.status, MeetingStatus.minutesReady);
      expect(meeting.source, MeetingSource.microphone);
      expect(meeting.finalizeStatus, FinalizeStatus.done);
      expect(meeting.transcriptSource, TranscriptSource.filetrans);
      expect(meeting.durationMs, 62000);
      expect(meeting.audioKey, 'mtg_v1_old');
      expect(meeting.hasMinutes, isTrue);
      // 新列默认值。
      expect(meeting.importStatus, ImportStatus.none);
      expect(meeting.importError, isNull);
      expect(meeting.importTaskId, isNull);
      expect(meeting.importMetaJson, isNull);
      // 子表存活（这是本迁移最大的风险点：DROP TABLE 的隐式 DELETE 级联）。
      expect(meeting.segments.length, 2);
      expect(meeting.segments[0].text, '旧库第一句');
      expect(meeting.segments[1].text, '旧库第二句');
      expect(meeting.speakers.length, 2);

      // 终稿原始 JSON 存活。
      expect(await repo.loadFiletransRaw('mtg_v1_old'), isNotNull);

      // 历史列表投影带上了 source / importStatus。
      final List<MeetingSummary> list = await repo.listMeetings();
      expect(list.single.source, MeetingSource.microphone);
      expect(list.single.importStatus, ImportStatus.none);
    });

    test('升级后可插入 source=imported 会议（v1 CHECK 会拒绝）', () async {
      buildV1Database();
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);
      final DriftMeetingRepository repo = DriftMeetingRepository(db);

      final Meeting imported = Meeting(
        id: 'mtg_imported_1',
        title: '导入的会议',
        createdAt: DateTime.now().toUtc(),
        durationMs: 12000,
        sampleRate: 16000,
        speakerCount: 0,
        status: MeetingStatus.stopped,
        source: MeetingSource.imported,
        finalizeStatus: FinalizeStatus.none,
        transcriptSource: TranscriptSource.realtime,
        audioStatus: AudioStatus.none,
        audioBytes: 0,
        minutesPartial: false,
        importStatus: ImportStatus.importPending,
        segments: const <TranscriptSegment>[],
        speakers: const <Speaker>[],
      );
      await repo.saveMeeting(imported);

      final Meeting? loaded = await repo.loadMeeting('mtg_imported_1');
      expect(loaded, isNotNull);
      expect(loaded!.source, MeetingSource.imported);
      expect(loaded.importStatus, ImportStatus.importPending);
    });

    test('PRAGMA table_info(meetings) 含 4 个新列，schema_meta 升到 2', () async {
      buildV1Database();
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      // 触发一次查询确保库已打开且迁移已跑。
      await db.customSelect('SELECT 1').get();

      final List<QueryRow> columns =
          await db.customSelect('PRAGMA table_info(meetings)').get();
      final Set<String> names = columns.map((QueryRow r) => r.read<String>('name')).toSet();
      expect(names, containsAll(<String>[
        'import_status',
        'import_error',
        'import_task_id',
        'import_meta_json',
      ]));

      final List<QueryRow> checkRows =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(checkRows, isEmpty, reason: '迁移后外键必须自洽');

      final int? version = await DriftMeetingRepository(db).schemaVersion();
      expect(version, 2);
    });

    test('新库直接建表即为 v2（onCreate 路径不受迁移影响）', () async {
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final DriftMeetingRepository repo = DriftMeetingRepository(db);

      final Meeting meeting = Meeting(
        id: 'mtg_fresh',
        title: '新库会议',
        createdAt: DateTime.now().toUtc(),
        durationMs: 0,
        sampleRate: 16000,
        speakerCount: 0,
        status: MeetingStatus.recording,
        source: MeetingSource.microphone,
        finalizeStatus: FinalizeStatus.none,
        transcriptSource: TranscriptSource.realtime,
        audioStatus: AudioStatus.none,
        audioBytes: 0,
        minutesPartial: false,
        segments: const <TranscriptSegment>[],
        speakers: const <Speaker>[],
      );
      await repo.saveMeeting(meeting);
      expect((await repo.loadMeeting('mtg_fresh'))!.importStatus, ImportStatus.none);
      expect(await repo.schemaVersion(), kSchemaVersion);
    });
  });
}
