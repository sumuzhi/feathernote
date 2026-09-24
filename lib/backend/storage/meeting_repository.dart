/// 领域对象 ⇄ 行的映射与仓储门面（对应原 `server/src/services/persistence.js`）。
library;

import 'package:drift/drift.dart';

import '../../core/ext/markdown_ext.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import 'app_database.dart';
import 'schema.dart';
import 'tables/filetrans_raw.dart';

/// 会议仓储抽象（UI 与 services 的唯一存储入口）。
abstract class MeetingRepository {
  /// 保存会议（upsert meeting + segments + speakers）。
  Future<void> saveMeeting(Meeting meeting);

  /// **窄更新纪要**：只更新纪要相关字段（`minutes_md` / `status` /
  /// `minutes_partial` / `minutes_error`），**绝不回写** `segments` / `speakers` /
  /// `duration_ms` / `audio_key` / `finalize_status`。
  ///
  /// 语义：
  /// - 传 `null` 表示**保持原值不变**；
  /// - 需要清空 `minutes_error` 时显式传 `clearMinutesError: true`；
  /// - 会议不存在时静默返回。
  ///
  /// 这是「纪要生成落盘」的唯一写入路径 —— 从根上杜绝「读整对象 → 改 → 整体
  /// 写回」用过期副本覆盖逐字稿（曾导致落库 segments 被擦成 0）。
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  });

  /// 读取会议（不存在返回 null）。
  Future<Meeting?> loadMeeting(String id);

  /// 历史列表（按 `created_at` DESC）。
  Future<List<MeetingSummary>> listMeetings();

  /// 删除会议（级联删除由 `ON DELETE CASCADE` 保证）。
  Future<void> deleteMeeting(String id);

  /// 修改标题。
  Future<void> updateTitle(String id, String title);

  /// 落库终稿原始 JSON。
  Future<void> saveFiletransRaw(String meetingId, String json);

  /// 读取终稿原始 JSON（不存在返回 null）。
  Future<String?> loadFiletransRaw(String meetingId);

  /// 反应式订阅历史列表（drift 流）。
  Stream<List<MeetingSummary>> watchMeetings();

  /// 反应式订阅某会议的片段列表。
  Stream<List<TranscriptSegment>> watchSegments(String meetingId);

  /// 读取 schema 版本（来自 `schema_meta`）。
  Future<int?> schemaVersion();
}

/// 基于 drift 的仓储实现。
class DriftMeetingRepository implements MeetingRepository {
  /// 构造仓储。
  const DriftMeetingRepository(this.db);

  /// 数据库实例。
  final AppDatabase db;

  @override
  Future<void> saveMeeting(Meeting meeting) async {
    try {
      await db.transaction(() async {
        await db.meetingDao.upsert(meetingRowFromDomain(meeting));
        await db.segmentDao.upsertMany(segmentRowsFromDomain(meeting));
        await db.speakerDao.replaceAll(meeting.id, speakerRowsFromDomain(meeting));
      });
    } catch (error) {
      logWarn('storage', '会议落盘失败 meeting=${meeting.id}：$error');
      rethrow;
    }
    logInfo(
      'storage',
      '会议已落盘',
      <String, Object?>{
        'id': meeting.id,
        'meetings': 1,
        'segments': meeting.segments.length,
        'speakers': meeting.speakers.length,
        'finalizeStatus': meeting.finalizeStatus.value,
      },
    );
  }

  @override
  Future<Meeting?> loadMeeting(String id) async {
    final MeetingRow? row = await db.meetingDao.getById(id);
    if (row == null) return null;
    final List<TranscriptSegmentRow> segments = await db.segmentDao.listByMeeting(id);
    final List<SpeakerRow> speakers = await db.speakerDao.listByMeeting(id);
    return meetingFromRow(row, segments, speakers);
  }

  @override
  Future<void> updateMinutes(
    String id, {
    String? minutesMd,
    MeetingStatus? status,
    bool? minutesPartial,
    String? minutesError,
    bool clearMinutesError = false,
  }) async {
    final MeetingRow? row = await db.meetingDao.getById(id);
    if (row == null) {
      logWarn('storage', '窄更新纪要：会议不存在 id=$id');
      return;
    }
    // 只算纪要四列；其余列（segments / speakers / 终稿 / 音频）一律不碰。
    final String nextStatus = (status ?? MeetingStatus.fromValue(row.status)).value;
    final int nextPartial = (minutesPartial ?? (row.minutesPartial != 0)) ? 1 : 0;
    final String? nextError =
        clearMinutesError ? null : (minutesError ?? row.minutesError);
    await db.meetingDao.updateMinutes(
      id,
      minutesMd: minutesMd ?? row.minutesMd,
      status: nextStatus,
      minutesPartial: nextPartial,
      minutesError: nextError,
    );
    logInfo(
      'storage',
      '纪要已窄更新（只写纪要列）',
      <String, Object?>{
        'id': id,
        'minutesChars': (minutesMd ?? row.minutesMd ?? '').length,
        'status': nextStatus,
        'partial': nextPartial,
      },
    );
  }

  @override
  Future<List<MeetingSummary>> listMeetings() async {
    final List<MeetingRow> rows = await db.meetingDao.listAll();
    return rows.map(summaryFromRow).toList(growable: false);
  }

  @override
  Stream<List<MeetingSummary>> watchMeetings() {
    return db.meetingDao.watchAll().map((List<MeetingRow> rows) {
      return rows.map(summaryFromRow).toList(growable: false);
    });
  }

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) {
    return db.segmentDao.watchByMeeting(meetingId).map((List<TranscriptSegmentRow> rows) {
      return rows.map((TranscriptSegmentRow row) => segmentFromRow(row)).toList(growable: false);
    });
  }

  @override
  Future<void> deleteMeeting(String id) async {
    await db.meetingDao.deleteById(id);
    logInfo('storage', '会议已删除', <String, Object?>{'id': id});
  }

  @override
  Future<void> updateTitle(String id, String title) async {
    await db.meetingDao.updateTitle(id, title);
  }

  @override
  Future<void> saveFiletransRaw(String meetingId, String json) async {
    await db
        .into(db.filetransRaw)
        .insert(
          FiletransRawCompanion.insert(
            meetingId: meetingId,
            json: json,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<String?> loadFiletransRaw(String meetingId) async {
    final FiletransRawRow? row =
        await (db.select(db.filetransRaw)
              ..where((FiletransRaw tbl) => tbl.meetingId.equals(meetingId)))
            .getSingleOrNull();
    return row?.json;
  }

  @override
  Future<int?> schemaVersion() async {
    try {
      final List<QueryRow> rows = await db
          .customSelect("SELECT value FROM schema_meta WHERE key = '$kSchemaMetaVersionKey'")
          .get();
      if (rows.isEmpty) return null;
      return int.tryParse(rows.first.read<String>('value'));
    } catch (error) {
      logWarn('storage', '读取 schema_meta 失败：$error');
      return null;
    }
  }

  // ── 映射（纯函数，可单测）──

  /// 领域 → 行。
  static MeetingsCompanion meetingRowFromDomain(Meeting meeting) {
    return MeetingsCompanion.insert(
      id: meeting.id,
      title: meeting.title,
      createdAt: meeting.createdAt.toUtc().toIso8601String(),
      durationMs: Value<int>(meeting.durationMs),
      sampleRate: Value<int>(meeting.sampleRate),
      speakerCount: Value<int>(meeting.speakerCount),
      minutesMd: Value<String?>(meeting.minutesMd),
      minutesPartial: Value<int>(meeting.minutesPartial ? 1 : 0),
      minutesError: Value<String?>(meeting.minutesError),
      status: Value<String>(meeting.status.value),
      source: Value<String>(meeting.source.value),
      finalizeStatus: Value<String>(meeting.finalizeStatus.value),
      transcriptSource: Value<String>(meeting.transcriptSource.value),
      finalizeError: Value<String?>(meeting.finalizeError),
      audioStatus: Value<String>(meeting.audioStatus.value),
      audioKey: Value<String?>(meeting.audioKey),
      audioError: Value<String?>(meeting.audioError),
      audioBytes: Value<int>(meeting.audioBytes),
    );
  }

  /// 领域片段 → 行（批量）。
  static List<TranscriptSegmentsCompanion> segmentRowsFromDomain(Meeting meeting) {
    return meeting.segments
        .map(
          (TranscriptSegment segment) => TranscriptSegmentsCompanion.insert(
            meetingId: meeting.id,
            segmentId: segment.segmentId,
            ordinal: segment.ordinal,
            speakerId: segment.speakerId,
            speakerName: Value<String?>(segment.speakerName),
            // 注意：Dart getter 是 `segmentText`（落库列名 `text`，见 tables/transcript_segments.dart）。
            segmentText: Value<String>(segment.text),
            startTime: Value<int>(segment.startTime),
            endTime: Value<int>(segment.endTime),
            confidence: Value<double>(segment.confidence),
            seqStart: Value<int>(segment.seqStart),
            seqEnd: Value<int>(segment.seqEnd),
          ),
        )
        .toList(growable: false);
  }

  /// 领域说话人 → 行（批量）。
  static List<SpeakersCompanion> speakerRowsFromDomain(Meeting meeting) {
    return meeting.speakers
        .map(
          (Speaker speaker) => SpeakersCompanion.insert(
            meetingId: meeting.id,
            speakerId: speaker.speakerId,
            name: speaker.name,
            colorIndex: Value<int>(speaker.colorIndex),
            firstSeenMs: Value<int>(speaker.firstSeenMs),
          ),
        )
        .toList(growable: false);
  }

  /// 行 → 领域会议。
  static Meeting meetingFromRow(
    MeetingRow row,
    List<TranscriptSegmentRow> segments,
    List<SpeakerRow> speakers,
  ) {
    return Meeting(
      id: row.id,
      title: row.title,
      createdAt: DateTime.tryParse(row.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: row.durationMs,
      sampleRate: row.sampleRate,
      speakerCount: row.speakerCount,
      minutesMd: row.minutesMd,
      minutesPartial: row.minutesPartial != 0,
      minutesError: row.minutesError,
      status: MeetingStatus.fromValue(row.status),
      source: MeetingSource.fromValue(row.source),
      finalizeStatus: FinalizeStatus.fromValue(row.finalizeStatus),
      transcriptSource: TranscriptSource.fromValue(row.transcriptSource),
      finalizeError: row.finalizeError,
      audioStatus: AudioStatus.fromValue(row.audioStatus),
      audioKey: row.audioKey,
      audioError: row.audioError,
      audioBytes: row.audioBytes,
      segments: segments.map(segmentFromRow).toList(growable: false),
      speakers: speakers.map(speakerFromRow).toList(growable: false),
    );
  }

  /// 行 → 领域片段。
  static TranscriptSegment segmentFromRow(TranscriptSegmentRow row) => TranscriptSegment(
    meetingId: row.meetingId,
    segmentId: row.segmentId,
    ordinal: row.ordinal,
    speakerId: row.speakerId,
    speakerName: row.speakerName,
    text: row.segmentText,
    startTime: row.startTime,
    endTime: row.endTime,
    confidence: row.confidence,
    seqStart: row.seqStart,
    seqEnd: row.seqEnd,
  );

  /// 行 → 领域说话人。
  static Speaker speakerFromRow(SpeakerRow row) => Speaker(
    meetingId: row.meetingId,
    speakerId: row.speakerId,
    name: row.name,
    colorIndex: row.colorIndex,
    firstSeenMs: row.firstSeenMs,
  );

  /// 行 → 历史列表投影（对应 `toSummary`）。
  static MeetingSummary summaryFromRow(MeetingRow row) => MeetingSummary(
    id: row.id,
    title: row.title,
    createdAt: DateTime.tryParse(row.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0),
    durationMs: row.durationMs,
    speakerCount: row.speakerCount,
    status: MeetingStatus.fromValue(row.status),
    finalizeStatus: FinalizeStatus.fromValue(row.finalizeStatus),
    hasMinutes: row.minutesMd != null && row.minutesMd!.trim().isNotEmpty && row.minutesPartial == 0,
    minutesPartial: row.minutesPartial != 0,
    minutesExcerpt: minutesExcerpt(row.minutesMd),
  );
}
