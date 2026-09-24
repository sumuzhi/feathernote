/// `transcript_segments` 表的数据访问对象。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/transcript_segments.dart';

part 'segment_dao.g.dart';

/// 片段 DAO。
@DriftAccessor(tables: <Type>[TranscriptSegments])
class SegmentDao extends DatabaseAccessor<AppDatabase> with _$SegmentDaoMixin {
  /// 构造 DAO。
  SegmentDao(super.attachedDatabase);

  /// 按会议查询 + 按 `start_time`、`segment_id` 升序的构造器。
  SimpleSelectStatement<TranscriptSegments, TranscriptSegmentRow> _ordered(String meetingId) =>
      select(transcriptSegments)
        ..where((TranscriptSegments tbl) => tbl.meetingId.equals(meetingId))
        ..orderBy(<OrderingTerm Function(TranscriptSegments)>[
          (TranscriptSegments tbl) => OrderingTerm.asc(tbl.startTime),
          (TranscriptSegments tbl) => OrderingTerm.asc(tbl.segmentId),
        ]);

  /// 按会议列出全部片段（按 `start_time`、`segment_id` 升序）。
  Future<List<TranscriptSegmentRow>> listByMeeting(String meetingId) => _ordered(meetingId).get();

  /// 反应式订阅某会议的片段列表。
  Stream<List<TranscriptSegmentRow>> watchByMeeting(String meetingId) => _ordered(meetingId).watch();

  /// 插入或替换单条片段（实时逐字稿 upsert 用）。
  Future<void> upsert(TranscriptSegmentsCompanion row) =>
      into(transcriptSegments).insert(row, mode: InsertMode.insertOrReplace);

  /// 批量 upsert。
  Future<void> upsertMany(List<TranscriptSegmentsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((Batch batch) {
      batch.insertAll(transcriptSegments, rows, mode: InsertMode.insertOrReplace);
    });
  }

  /// 全量替换某会议的片段（终稿回填：先删后插，保证不残留旧句）。
  Future<void> replaceAll(String meetingId, List<TranscriptSegmentsCompanion> rows) async {
    await transaction(() async {
      await (delete(transcriptSegments)
        ..where((TranscriptSegments tbl) => tbl.meetingId.equals(meetingId))).go();
      if (rows.isEmpty) return;
      await batch((Batch batch) {
        batch.insertAll(transcriptSegments, rows, mode: InsertMode.insertOrReplace);
      });
    });
  }

  /// 删除某会议的全部片段。
  Future<int> deleteByMeeting(String meetingId) =>
      (delete(transcriptSegments)
        ..where((TranscriptSegments tbl) => tbl.meetingId.equals(meetingId))).go();
}
