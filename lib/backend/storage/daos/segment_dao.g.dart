// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'segment_dao.dart';

// ignore_for_file: type=lint
mixin _$SegmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $MeetingsTable get meetings => attachedDatabase.meetings;
  $TranscriptSegmentsTable get transcriptSegments =>
      attachedDatabase.transcriptSegments;
  SegmentDaoManager get managers => SegmentDaoManager(this);
}

class SegmentDaoManager {
  final _$SegmentDaoMixin _db;
  SegmentDaoManager(this._db);
  $$MeetingsTableTableManager get meetings =>
      $$MeetingsTableTableManager(_db.attachedDatabase, _db.meetings);
  $$TranscriptSegmentsTableTableManager get transcriptSegments =>
      $$TranscriptSegmentsTableTableManager(
        _db.attachedDatabase,
        _db.transcriptSegments,
      );
}
