/// `filetrans_raw` 表的 drift 定义（终稿原始 JSON 审计件）。
library;

import 'package:drift/drift.dart';

import 'meetings.dart';

/// 终稿原始 JSON 表（单行 / 会议，供审计与重跑映射）。
///
/// `@DataClassName('FiletransRawRow')`：表名 `FiletransRaw` 无法被 drift 自动单数化，
/// 默认会生成 `FiletransRawData`，这里显式统一为 `XxxRow` 命名。
@DataClassName('FiletransRawRow')
class FiletransRaw extends Table {
  /// 所属会议 ID（主键）。
  TextColumn get meetingId => text().references(Meetings, #id, onDelete: KeyAction.cascade)();

  /// 原始 JSON 文本。
  TextColumn get json => text()();

  /// 落库时间（ISO 8601 UTC）。
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>>? get primaryKey => <Column<Object>>{meetingId};

  @override
  String get tableName => 'filetrans_raw';
}
