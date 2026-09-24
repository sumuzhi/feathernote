/// `speakers` 表的数据访问对象。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/speakers.dart';

part 'speaker_dao.g.dart';

/// 说话人 DAO。
@DriftAccessor(tables: <Type>[Speakers])
class SpeakerDao extends DatabaseAccessor<AppDatabase> with _$SpeakerDaoMixin {
  /// 构造 DAO。
  SpeakerDao(super.attachedDatabase);

  /// 按会议查询 + 按 `first_seen_ms` 升序的构造器。
  SimpleSelectStatement<Speakers, SpeakerRow> _ordered(String meetingId) =>
      select(speakers)
        ..where((Speakers tbl) => tbl.meetingId.equals(meetingId))
        ..orderBy(<OrderingTerm Function(Speakers)>[(Speakers tbl) => OrderingTerm.asc(tbl.firstSeenMs)]);

  /// 按会议列出说话人（按 `first_seen_ms` 升序）。
  Future<List<SpeakerRow>> listByMeeting(String meetingId) => _ordered(meetingId).get();

  /// 反应式订阅某会议的说话人表。
  Stream<List<SpeakerRow>> watchByMeeting(String meetingId) => _ordered(meetingId).watch();

  /// 全量替换某会议的说话人表（终稿重算后调用）。
  Future<void> replaceAll(String meetingId, List<SpeakersCompanion> rows) async {
    await transaction(() async {
      await (delete(speakers)..where((Speakers tbl) => tbl.meetingId.equals(meetingId))).go();
      if (rows.isEmpty) return;
      await batch((Batch batch) {
        batch.insertAll(speakers, rows, mode: InsertMode.insertOrReplace);
      });
    });
  }
}
