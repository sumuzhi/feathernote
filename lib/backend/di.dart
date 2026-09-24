/// 依赖装配（进程内）：把配置、引擎、存储、服务组装成唯一的 [BackendApi] 门面。
///
/// 对应主理人决策「方案 ②：以进程内调用为主」。UI 只持有 [BackendApi]，
/// 因此后续如需切到 debug 适配层（`--dart-define=ENABLE_LOCAL_HTTP=true`），
/// 只替换本文件返回的实现即可，UI 零改动。
library;

import '../core/config/app_config.dart';
import '../core/log/log.dart';
import 'backend_api.dart';
import 'engine/bailian/bailian_engine.dart';
import 'engine/engine.dart';
import 'engine/mock/mock_engine.dart';
import 'services/finalize_poller.dart';
import 'services/minutes_service.dart';
import 'services/session_store.dart';
import 'services/transcription_service.dart';
import 'storage/app_database.dart';
import 'storage/audio_archive.dart';
import 'storage/meeting_repository.dart';

/// 装配结果（含需要随 UI 生命周期释放的资源）。
class BackendBundle {
  /// 构造装配结果。
  const BackendBundle({
    required this.api,
    required this.database,
    required this.config,
    required this.engineName,
    required this.degradedReason,
  });

  /// 对外唯一门面。
  final BackendApi api;

  /// 主数据库（释放时需 `close()`）。
  final AppDatabase database;

  /// 冻结配置（只读展示用，如「我的」页面）。
  final AppConfig config;

  /// 实际使用的引擎名（`bailian` / `mock`）。
  final String engineName;

  /// 非空表示「因配置问题降级到 Mock 引擎」的原因，供 UI 明确提示。
  final String? degradedReason;

  /// 是否处于降级（Mock）状态。
  bool get isDegraded => degradedReason != null;

  /// 释放全部资源。
  Future<void> dispose() async {
    await api.dispose();
    await database.close();
  }
}

/// 组装后端依赖图（幂等：每次调用创建独立实例，调用方负责 [BackendBundle.dispose]）。
///
/// 引擎选择规则（与 `AppConfig.validate()` 的强校验语义配合）：
/// - `ENGINE_PROVIDER=mock` 或显式 `USE_MOCK_ENGINE=true` → [MockEngine]；
/// - 配置校验不通过（如缺 `DASHSCOPE_API_KEY`）→ **显式降级**到 [MockEngine]，
///   并把原因写入 [BackendBundle.degradedReason]，由 UI 顶部提示条告知用户
///   （不静默回落：用户看得见「现在跑的是 mock」）。
Future<BackendBundle> createBackend({AppConfig? config}) async {
  final AppConfig cfg = config ?? AppConfig.defaults();
  cfg.applyLogLevel();

  // 启动即回显「实际生效的全部模型名」——模型名写错（如实时线误用 3.1）
  // 是"实时零句子 / 逐字稿为空"的高发根因，必须在第一屏日志里可见。
  logInfo('config', '生效模型 ${cfg.describeModels()}');

  final List<String> problems = cfg.validate();
  final String? degradedReason = problems.isEmpty ? null : problems.first;
  final bool useMock = cfg.useMockEngine || degradedReason != null;
  final Engine engine = useMock ? MockEngine() : BailianEngine(cfg);

  final AppDatabase database = AppDatabase();
  final MeetingRepository persistence = DriftMeetingRepository(database);
  final AudioArchive archive = LocalFileArchive();
  final SessionStore sessionStore = SessionStore();

  final TranscriptionService transcriptionService = TranscriptionService(
    engine: engine,
    sessionStore: sessionStore,
    persistence: persistence,
    archive: archive,
    cfg: cfg,
  );

  final FinalizePoller finalizePoller = FinalizePoller(
    engine: engine,
    persistence: persistence,
    cfg: cfg,
    onComplete: transcriptionService.handleFinalizeComplete,
    onProgress: (String meetingId, String status, String? taskId) {
      transcriptionService.emitFinalizeProgress(meetingId, status, taskId: taskId);
    },
    onFailed: (String meetingId, Object error) {
      transcriptionService.emitFinalizeProgress(
        meetingId,
        'failed',
        error: MinutesService.readableError(error),
      );
    },
  );
  transcriptionService.attachFinalizePoller(finalizePoller);

  final MinutesService minutesService = MinutesService(
    engine: engine,
    persistence: persistence,
    cfg: cfg,
  );

  final BackendApiImpl api = BackendApiImpl(
    cfg: cfg,
    engine: engine,
    persistence: persistence,
    sessionStore: sessionStore,
    transcriptionService: transcriptionService,
    minutesService: minutesService,
    finalizePoller: finalizePoller,
    archive: archive,
  );
  await api.init();

  logInfo(
    'di',
    '后端已装配 engine=${engine.name}${degradedReason == null ? '' : '（降级：$degradedReason）'}',
  );
  return BackendBundle(
    api: api,
    database: database,
    config: cfg,
    engineName: engine.name,
    degradedReason: degradedReason,
  );
}
