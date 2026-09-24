/// 后端门面 `BackendApi`：**UI 的唯一入口**（对应原 `/api/*` + `/ws/audio` 的全部能力）。
///
/// 三个作用：
/// 1. UI 只依赖它 → 切换「进程内调用」与「本地 HTTP 适配层」两种传输形态不影响 UI；
/// 2. debug 适配层（`LocalHttpServer`）只依赖它 → 适配层不含业务逻辑；
/// 3. 单测可注入 `FakeBackendApi` → UI 可脱离网络测试。
library;

import 'dart:typed_data';

import '../core/config/app_config.dart';
import '../core/error/app_error.dart';
import '../core/ids.dart';
import '../core/log/log.dart';
import '../core/pcm/audio_frame.dart';
import '../domain/enums.dart';
import '../domain/meeting.dart';
import '../domain/segment.dart';
import '../domain/speaker.dart';
import 'engine/engine.dart';
import 'services/finalize_poller.dart';
import 'services/minutes_service.dart';
import 'services/session_store.dart';
import 'services/transcription_service.dart';
import 'storage/audio_archive.dart';
import 'storage/meeting_repository.dart';

/// 健康检查状态（对应 `/api/health`）。
class HealthStatus {
  /// 构造健康状态。
  const HealthStatus({
    required this.ok,
    required this.engineName,
    required this.schemaVersion,
    required this.meetingCount,
    this.message,
  });

  /// 是否健康。
  final bool ok;

  /// 引擎名（`bailian` / `mock`）。
  final String engineName;

  /// schema 版本（null 表示未读到 `schema_meta`）。
  final int? schemaVersion;

  /// 会议数量。
  final int meetingCount;

  /// 附加说明（不健康时为原因）。
  final String? message;

  /// 转为 JSON（debug 适配层直接输出）。
  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    'engine': engineName,
    'schema_version': schemaVersion,
    'meeting_count': meetingCount,
    'message': message,
  };
}

/// 后端门面抽象。
abstract class BackendApi {
  /// 初始化（建库 / 预热）。
  Future<void> init();

  /// 释放资源。
  Future<void> dispose();

  // ── 会议 CRUD（对应 /api/meetings*）──

  /// 创建会议（默认 `recording` 状态）。
  Future<Meeting> createMeeting({required String title, int sampleRate = 16000});

  /// 历史列表。
  Future<List<MeetingSummary>> listMeetings();

  /// 读取会议（不存在返回 null）。
  Future<Meeting?> getMeeting(String id);

  /// 修改标题。
  Future<Meeting> updateMeeting(String id, {String? title});

  /// 删除会议。
  Future<void> deleteMeeting(String id);

  // ── 录音会话（对应 /ws/audio）──

  /// 开始录音（建会话 + 开实时 ASR）。
  Future<void> startRecording({required String meetingId, required String sessionId, String? title});

  /// 推送一帧音频（20ms/640B）。
  void pushAudioFrame(AudioFrame frame);

  /// 停止录音（收尾 → 写 WAV → 归档 → 触发终稿）。
  Future<void> stopRecording(String meetingId);

  // ── 终稿（对应 /api/meetings/:id/finalize）──

  /// 手动触发终稿转写。
  Future<void> startFinalize(String meetingId, {required String wavPath});

  // ── 纪要（对应 /api/meetings/:id/minutes[/stream]）──

  /// 非流式生成纪要。
  Future<String> generateMinutes(String meetingId);

  /// 流式生成纪要（打字机）。
  Stream<String> generateMinutesStream(String meetingId, {bool force = false});

  // ── 音频（对应 /api/meetings/:id/audio）──

  /// 读取归档音频字节（不存在返回 null）。
  Future<Uint8List?> getAudio(String meetingId);

  /// 解析归档音频的本地可播放路径。
  Future<String?> getAudioPath(String meetingId);

  // ── 反应式流 ──

  /// 事件流（实时转写 / 终稿替换 / 会议状态 / 引擎错误）。
  Stream<TranscriptEvent> get events;

  /// 历史列表流（写库即刷新）。
  Stream<List<MeetingSummary>> watchMeetings();

  /// 会议片段流。
  Stream<List<TranscriptSegment>> watchSegments(String meetingId);

  // ── 健康检查（对应 /api/health）──

  /// 健康检查。
  Future<HealthStatus> health();
}

/// 门面默认实现（进程内调用 Services，无 HTTP 传输层）。
class BackendApiImpl implements BackendApi {
  /// 构造门面。
  BackendApiImpl({
    required this.cfg,
    required this.engine,
    required this.persistence,
    required this.sessionStore,
    required this.transcriptionService,
    required this.minutesService,
    required this.finalizePoller,
    required this.archive,
  });

  /// 冻结配置。
  final AppConfig cfg;

  /// 引擎。
  final Engine engine;

  /// 持久化门面。
  final MeetingRepository persistence;

  /// 会话态。
  final SessionStore sessionStore;

  /// 转写服务。
  final TranscriptionService transcriptionService;

  /// 纪要服务。
  final MinutesService minutesService;

  /// 终稿轮询器。
  final FinalizePoller finalizePoller;

  /// 音频归档。
  final AudioArchive archive;

  @override
  Future<void> init() async {
    logInfo('backend', 'BackendApi 初始化完成 engine=${engine.name}');
  }

  @override
  Future<void> dispose() async {
    await transcriptionService.dispose();
    await engine.dispose();
    sessionStore.clear();
    logInfo('backend', 'BackendApi 已释放');
  }

  @override
  Future<Meeting> createMeeting({required String title, int sampleRate = 16000}) async {
    final Meeting meeting = Meeting(
      id: genMeetingId(),
      title: title.isEmpty ? '未命名会议' : title,
      createdAt: DateTime.now().toUtc(),
      durationMs: 0,
      sampleRate: sampleRate,
      speakerCount: 0,
      status: MeetingStatus.recording,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.none,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.none,
      audioBytes: 0,
      minutesPartial: false,
      segments: const <TranscriptSegment>[],
      speakers: const <Speaker>[],
    );
    await persistence.saveMeeting(meeting);
    logInfo('backend', '会议已创建 id=${meeting.id} title=${meeting.title}');
    return meeting;
  }

  @override
  Future<List<MeetingSummary>> listMeetings() => persistence.listMeetings();

  @override
  Future<Meeting?> getMeeting(String id) => persistence.loadMeeting(id);

  @override
  Future<Meeting> updateMeeting(String id, {String? title}) async {
    final Meeting? meeting = await persistence.loadMeeting(id);
    if (meeting == null) throw AppError(ErrorCode.notFound, '会议不存在：$id');
    if (title != null && title.isNotEmpty) {
      await persistence.updateTitle(id, title);
    }
    return (await persistence.loadMeeting(id)) ?? meeting;
  }

  @override
  Future<void> deleteMeeting(String id) async {
    final Meeting? meeting = await persistence.loadMeeting(id);
    if (meeting == null) throw AppError(ErrorCode.notFound, '会议不存在：$id');
    final String? key = meeting.audioKey;
    if (key != null && key.isNotEmpty) {
      await archive.remove(key);
    }
    await persistence.deleteMeeting(id);
  }

  @override
  Future<void> startRecording({
    required String meetingId,
    required String sessionId,
    String? title,
  }) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) throw AppError(ErrorCode.notFound, '会议不存在：$meetingId');
    await transcriptionService.startSession(
      sessionId: sessionId,
      meetingId: meetingId,
      title: title ?? meeting.title,
      sampleRate: meeting.sampleRate,
    );
    // 绑定活动会话：`pushAudioFrame` 依赖它定位会话（否则音频帧会被丢弃）。
    _activeSessionId = sessionId;
    _activeMeetingId = meetingId;
  }

  @override
  void pushAudioFrame(AudioFrame frame) {
    final String? sessionId = _activeSessionId;
    if (sessionId == null) {
      logWarn('backend', '收到音频帧但没有活动会话，已丢弃');
      return;
    }
    transcriptionService.onAudioFrame(sessionId, frame);
  }

  /// 当前活动会话（开始录音时绑定，停止时清空）。
  String? _activeSessionId;

  /// 当前活动会议。
  String? _activeMeetingId;

  /// 当前活动会话 ID（供 UI / debug 层读取）。
  String? get activeSessionId => _activeSessionId;

  /// 当前活动会议 ID（供 UI / debug 层读取）。
  String? get activeMeetingId => _activeMeetingId;

  @override
  Future<void> stopRecording(String meetingId) async {
    await transcriptionService.onStop(meetingId);
    _activeSessionId = null;
    _activeMeetingId = null;
  }

  @override
  Future<void> startFinalize(String meetingId, {required String wavPath}) =>
      transcriptionService.startFinalize(meetingId, wavPath: wavPath);

  @override
  Future<String> generateMinutes(String meetingId) => minutesService.generate(meetingId);

  @override
  Stream<String> generateMinutesStream(String meetingId, {bool force = false}) =>
      minutesService.generateStream(meetingId, force: force);

  @override
  Future<Uint8List?> getAudio(String meetingId) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    final String? key = meeting?.audioKey;
    if (key == null || key.isEmpty) return null;
    return archive.get(key);
  }

  @override
  Future<String?> getAudioPath(String meetingId) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    final String? key = meeting?.audioKey;
    if (key == null || key.isEmpty) return null;
    return archive.localPath(key);
  }

  @override
  Stream<TranscriptEvent> get events => transcriptionService.events;

  @override
  Stream<List<MeetingSummary>> watchMeetings() => persistence.watchMeetings();

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) =>
      persistence.watchSegments(meetingId);

  @override
  Future<HealthStatus> health() async {
    final List<MeetingSummary> meetings = await persistence.listMeetings();
    final int? version = await persistence.schemaVersion();
    return HealthStatus(
      ok: true,
      engineName: engine.name,
      schemaVersion: version,
      meetingCount: meetings.length,
      message: 'ok',
    );
  }
}
