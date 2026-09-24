/// `meetings` 表的 drift 定义（字段与 [kSchemaSql] 逐字对应）。
library;

import 'package:drift/drift.dart';

/// 会议主表。
///
/// CHECK 约束由 `onCreate` 执行的原始 DDL 保证（drift 的 table class 只生成查询代码）。
///
/// `@DataClassName` 显式指定生成类为 `MeetingRow`：
/// ① 与 `domain/meeting.dart` 的领域模型 `Meeting` 区分开，避免两个 `Meeting` 造成
///    `ambiguous_import`（存储层与领域层同名会让每个消费文件都要加前缀）；
/// ② 存储层统一使用 `XxxRow` 命名（见 `Meetings` / `Speakers` / `TranscriptSegments` / `FiletransRaw`）。
@DataClassName('MeetingRow')
class Meetings extends Table {
  /// 会议 ID（`mtg_...`）。
  TextColumn get id => text()();

  /// 标题。
  TextColumn get title => text()();

  /// 创建时间（ISO 8601 UTC）。
  TextColumn get createdAt => text()();

  /// 时长（毫秒）。
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// 实际采样率。
  IntColumn get sampleRate => integer().withDefault(const Constant(16000))();

  /// 说话人数量。
  IntColumn get speakerCount => integer().withDefault(const Constant(0))();

  /// 纪要 Markdown。
  TextColumn get minutesMd => text().nullable()();

  /// 纪要是否为残篇（0/1）。
  IntColumn get minutesPartial => integer().withDefault(const Constant(0))();

  /// 纪要生成失败原因。
  TextColumn get minutesError => text().nullable()();

  /// 状态：`recording` / `stopped` / `minutes_ready`。
  TextColumn get status => text().withDefault(const Constant('recording'))();

  /// 来源：`microphone` / `upload`。
  TextColumn get source => text().withDefault(const Constant('microphone'))();

  /// 终稿状态。
  TextColumn get finalizeStatus => text().withDefault(const Constant('none'))();

  /// 逐字稿来源。
  TextColumn get transcriptSource => text().withDefault(const Constant('realtime'))();

  /// 终稿失败原因。
  TextColumn get finalizeError => text().nullable()();

  /// 音频归档状态。
  TextColumn get audioStatus => text().withDefault(const Constant('none'))();

  /// 归档 key / 本地路径。
  TextColumn get audioKey => text().nullable()();

  /// 归档失败原因。
  TextColumn get audioError => text().nullable()();

  /// 音频字节数。
  IntColumn get audioBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>>? get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'meetings';
}
