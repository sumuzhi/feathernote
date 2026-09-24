/// `speakers` 表的 drift 定义。
library;

import 'package:drift/drift.dart';

import 'meetings.dart';

/// 说话人表。
///
/// `@DataClassName('SpeakerRow')`：与 `domain/speaker.dart` 的 `Speaker` 区分，避免重名歧义。
@DataClassName('SpeakerRow')
class Speakers extends Table {
  /// 所属会议 ID。
  TextColumn get meetingId => text().references(Meetings, #id, onDelete: KeyAction.cascade)();

  /// 说话人 ID（`spk_1` …）。
  TextColumn get speakerId => text()();

  /// 展示名。
  TextColumn get name => text()();

  /// 配色下标（0–5）。
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();

  /// 首次出现时间（毫秒）。
  IntColumn get firstSeenMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>>? get primaryKey => <Column<Object>>{meetingId, speakerId};

  @override
  String get tableName => 'speakers';
}
