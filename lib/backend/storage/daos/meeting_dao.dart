/// `meetings` 表的数据访问对象。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/meetings.dart';

part 'meeting_dao.g.dart';

/// 会议 DAO。
@DriftAccessor(tables: <Type>[Meetings])
class MeetingDao extends DatabaseAccessor<AppDatabase> with _$MeetingDaoMixin {
  /// 构造 DAO。
  MeetingDao(super.attachedDatabase);

  /// 按 `created_at` DESC 排序的查询构造器。
  SimpleSelectStatement<Meetings, MeetingRow> _ordered() =>
      select(meetings)
        ..orderBy(<OrderingTerm Function(Meetings)>[
          (Meetings tbl) => OrderingTerm.desc(tbl.createdAt),
        ]);

  /// 插入或替换一行。
  Future<void> upsert(MeetingsCompanion row) =>
      into(meetings).insert(row, mode: InsertMode.insertOrReplace);

  /// 按 ID 读取一行（不存在返回 null）。
  Future<MeetingRow?> getById(String id) =>
      (select(meetings)..where((Meetings tbl) => tbl.id.equals(id))).getSingleOrNull();

  /// 列出全部（按 `created_at` DESC）。
  Future<List<MeetingRow>> listAll() => _ordered().get();

  /// 反应式订阅全部会议（写库即刷新 UI）。
  Stream<List<MeetingRow>> watchAll() => _ordered().watch();

  /// 反应式订阅单个会议。
  Stream<MeetingRow?> watchById(String id) =>
      (select(meetings)..where((Meetings tbl) => tbl.id.equals(id))).watchSingleOrNull();

  /// 更新标题。
  Future<int> updateTitle(String id, String title) =>
      (update(meetings)..where((Meetings tbl) => tbl.id.equals(id))).write(
        MeetingsCompanion(title: Value<String>(title)),
      );

  /// **窄更新**：只写纪要相关列（`minutes_md` / `status` / `minutes_partial` /
  /// `minutes_error`），**绝不触碰** `segments` / `speakers` / `duration_ms` /
  /// `audio_key` / `finalize_status` 等列。
  ///
  /// 存在意义：纪要落盘若走「读整对象 → 改 → 整体写回」，会用一份**过期副本**
  /// 覆盖掉期间已落库的逐字稿（「读-改-写覆盖」；曾导致 segments 被擦成 0）。
  /// 用列级 UPDATE 从根上杜绝该类覆盖。
  Future<int> updateMinutes(
    String id, {
    required String? minutesMd,
    required String status,
    required int minutesPartial,
    required String? minutesError,
  }) =>
      (update(meetings)..where((Meetings tbl) => tbl.id.equals(id))).write(
        MeetingsCompanion(
          minutesMd: Value<String?>(minutesMd),
          status: Value<String>(status),
          minutesPartial: Value<int>(minutesPartial),
          minutesError: Value<String?>(minutesError),
        ),
      );

  /// 删除一行（子表由 `ON DELETE CASCADE` 清理）。
  Future<int> deleteById(String id) =>
      (delete(meetings)..where((Meetings tbl) => tbl.id.equals(id))).go();

  /// 统计行数。
  Future<int> countAll() async {
    final int? value = await meetings.count().getSingleOrNull();
    return value ?? 0;
  }
}
