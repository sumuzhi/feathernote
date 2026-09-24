/// `transcript_segments` 表的 drift 定义（复合主键 + 外键级联）。
///
/// ⚠️ 列名 `text` 与 drift `Table` 基类继承来的 `text()` 工厂**同名冲突**，
/// 故 Dart getter 命名为 `segmentText`，并显式 `.named('text')` 指定落库列名。
library;

import 'package:drift/drift.dart';

import 'meetings.dart';

/// 逐字稿片段表。
///
/// 复合主键 `(meeting_id, segment_id)`；删除会议时由 `ON DELETE CASCADE` 清理。
///
/// `@DataClassName('TranscriptSegmentRow')`：与 `domain/segment.dart` 的 `TranscriptSegment` 区分。
@DataClassName('TranscriptSegmentRow')
class TranscriptSegments extends Table {
  /// 所属会议 ID。
  TextColumn get meetingId => text().references(Meetings, #id, onDelete: KeyAction.cascade)();

  /// 片段 ID（会议内唯一）。
  TextColumn get segmentId => text()();

  /// 排序序号。
  IntColumn get ordinal => integer()();

  /// 说话人 ID。
  TextColumn get speakerId => text()();

  /// 说话人展示名（可空）。
  TextColumn get speakerName => text().nullable()();

  /// 文本（落库列名 `text`）。
  TextColumn get segmentText => text().named('text').withDefault(const Constant(''))();

  /// 起始时间（毫秒）。
  IntColumn get startTime => integer().withDefault(const Constant(0))();

  /// 结束时间（毫秒）。
  IntColumn get endTime => integer().withDefault(const Constant(0))();

  /// 置信度。
  RealColumn get confidence => real().withDefault(const Constant(0.9))();

  /// 起始帧序号。
  IntColumn get seqStart => integer().withDefault(const Constant(0))();

  /// 结束帧序号。
  IntColumn get seqEnd => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>>? get primaryKey => <Column<Object>>{meetingId, segmentId};

  @override
  String get tableName => 'transcript_segments';
}
