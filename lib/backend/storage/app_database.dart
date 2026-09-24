/// drift 数据库：4 张表 + 原始 DDL 建表（含 CHECK 约束与索引）。
///
/// 建表策略：为 100% 复刻原 schema（含 5 个 `CHECK`），`onCreate` 直接执行
/// [kSchemaSql] 原文，而不是用 drift 的 `createAll()`。
/// drift 的 table class 仅用于生成类型安全查询。
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/log/log.dart';
import 'daos/meeting_dao.dart';
import 'daos/segment_dao.dart';
import 'daos/speaker_dao.dart';
import 'schema.dart';
import 'tables/filetrans_raw.dart';
import 'tables/meetings.dart';
import 'tables/speakers.dart';
import 'tables/transcript_segments.dart';

part 'app_database.g.dart';

/// 应用主数据库。
@DriftDatabase(
  tables: <Type>[Meetings, TranscriptSegments, Speakers, FiletransRaw],
  daos: <Type>[MeetingDao, SegmentDao, SpeakerDao],
)
class AppDatabase extends _$AppDatabase {
  /// 构造：使用 `drift_flutter` 的后台 isolate 打开（避免阻塞 UI 线程）。
  AppDatabase() : super(driftDatabase(name: 'minutes'));

  /// 测试构造：传入自定义 executor（如 `NativeDatabase.memory()` / 临时文件库）。
  ///
  /// 注意：生成基类 `_$AppDatabase` 只转发 `super(QueryExecutor)`，没有 `connect` 命名构造，
  /// 因此这里接受 [QueryExecutor] 而不是 [DatabaseConnection]。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await customStatement(kForeignKeysOn);
      for (final String statement in kSchemaStatements) {
        await customStatement(statement);
      }
      await customStatement(
        "INSERT INTO schema_meta(key, value) VALUES('$kSchemaMetaVersionKey', '$kSchemaVersion')",
      );
      logInfo('storage', 'SQLite schema 初始化完成 version=$kSchemaVersion');
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 为首个版本，暂无增量迁移；后续版本在此追加 `if (from < N) ...`。
      logWarn('storage', 'schema 迁移 from=$from to=$to（v1 无增量 DDL）');
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement(kForeignKeysOn);
    },
  );
}
