/// 冻结配置类（1:1 对应原项目 `server/src/config.js` 的环境变量）。
///
/// 全部字段 `final`，构造后不可变；缺失必填项时 [validate] 返回明确错误，
/// **不做静默回落**（沿用原 Node 版 `validateConfig` 的强校验语义）。
library;

import '../log/log.dart';
import 'secrets.dart';

export 'secrets.dart' show Secrets;

// ── 实时模型白名单（根因防护：模型名写错 → 会话起不来 → 实时零句子） ──
//
// 背景：百炼 ASR 的**实时（streaming / realtime）**型号与**终稿（filetrans）**
// 型号是两套**互不相同**的白名单。历史上 `BAILIAN_REALTIME_MODEL` 被误写成
// `qwen-audio-3.1-asr-flash-streaming`（3.1 只存在于 filetrans 线），服务端
// `run-task` 直接拒绝 → 帧全堆在 `_pending` → 实时零句子 → 逐字稿为空。
// 这里做一次"收敛到白名单"的轻校验：不在白名单就回退并**醒目告警**。

/// 已知可用的**实时（streaming / realtime）** ASR 模型白名单。
///
/// 来源：阿里云百炼 ASR 官方模型列表（实时线）。**不含** filetrans 模型
/// （终稿线用的是 `qwen-audio-3.1-asr-flash-filetrans`，见 [AppConfig.filetransModel]）。
const Set<String> kKnownRealtimeModels = <String>{
  'qwen-audio-3.0-asr-flash-streaming',
  'qwen3-asr-flash-realtime',
  'fun-asr-realtime',
  'fun-asr-mtl-realtime',
  'fun-asr-flash-8k-realtime',
  'paraformer-realtime-v2',
  'paraformer-realtime-v1',
  'paraformer-realtime-8k-v2',
  'paraformer-realtime-8k-v1',
};

/// 实时模型缺省 / 回退默认值（白名单内、官方推荐、任意采样率且不限时长）。
const String kDefaultRealtimeModel = 'qwen-audio-3.0-asr-flash-streaming';

/// 实时模型解析结果：原值 / 采用值 / 是否发生回退。
class RealtimeModelResolution {
  /// 构造解析结果。
  const RealtimeModelResolution({
    required this.original,
    required this.effective,
    required this.fellBack,
  });

  /// 原始（配置里写的）值；空串表示未显式配置。
  final String original;

  /// 最终实际生效的值（一定在白名单内）。
  final String effective;

  /// 是否因原值不在白名单而发生了回退。
  final bool fellBack;
}

/// 把任意来源的实时模型名收敛到白名单内。
///
/// - 白名单内 → 原样采用；
/// - 不在白名单（如 `qwen-audio-3.1-asr-flash-streaming`）→ **回退**到
///   [kDefaultRealtimeModel]，并置 `fellBack = true`；
/// - 空串 → 采用默认值，但不视为"回退"（只是未配置）。
///
/// 该函数是纯函数，便于单测（P2 回归）。
RealtimeModelResolution resolveRealtimeModel(String? raw) {
  final String original = (raw ?? '').trim();
  if (original.isEmpty) {
    return const RealtimeModelResolution(
      original: '',
      effective: kDefaultRealtimeModel,
      fellBack: false,
    );
  }
  if (kKnownRealtimeModels.contains(original)) {
    return RealtimeModelResolution(
      original: original,
      effective: original,
      fellBack: false,
    );
  }
  return RealtimeModelResolution(
    original: original,
    effective: kDefaultRealtimeModel,
    fellBack: true,
  );
}

/// 全局冻结配置。
class AppConfig {
  /// 构造配置（所有字段显式给出，缺省值来自原 Node 版默认值）。
  const AppConfig({
    required this.engineProvider,
    required this.dashscopeApiKey,
    required this.dashscopeWorkspaceId,
    required this.bailianRegion,
    required this.realtimeModel,
    required this.realtimeWsUrl,
    required this.realtimeSampleRate,
    required this.realtimeFrameMs,
    required this.realtimeHeartbeat,
    required this.realtimeMaxSilenceMs,
    required this.realtimeSemanticPunct,
    required this.realtimeRingMs,
    required this.realtimeMaxRestart,
    required this.filetransModel,
    required this.bailianHttpBase,
    required this.filetransLanguageHints,
    required this.filetransDiarization,
    required this.filetransPollIntervalMs,
    required this.filetransTimeoutMs,
    required this.filetransMaxRetry,
    required this.uploadTimeoutMs,
    required this.uploadMaxRetry,
    required this.uploadMaxMb,
    this.importMaxMb = 2048,
    this.importMaxDurationHours = 12,
    this.importDiarizationSoftLimitHours = 2,
    required this.httpTimeoutMs,
    required this.llmModel,
    required this.llmEnableThinking,
    required this.llmBaseUrl,
    required this.llmTemperature,
    required this.llmMaxTokens,
    required this.llmTimeoutMs,
    required this.llmMaxRetry,
    required this.summaryStrategy,
    required this.speakerThreshold,
    required this.logLevel,
    required this.sampleRate,
    required this.audioStorage,
    required this.enableLocalHttp,
    required this.localHttpPort,
    required this.useMockEngine,
    required this.version,
    required this.buildStamp,
  });

  // ── 引擎 ──

  /// 运行时引擎提供方（`bailian` | `mock`）。
  final String engineProvider;

  // ── 百炼鉴权 / 地域 ──

  /// 百炼 API Key。
  final String dashscopeApiKey;

  /// 百炼 Workspace ID（空 = 公共域名）。
  final String dashscopeWorkspaceId;

  /// 地域，默认 `cn-beijing`。
  final String bailianRegion;

  // ── 实时流式 ASR ──

  /// 实时模型名。
  final String realtimeModel;

  /// 实时 WS URL（空 = 按地域/Workspace 推导）。
  final String realtimeWsUrl;

  /// 实时采样率（请求值；实际值可能不同，见 U1）。
  final int realtimeSampleRate;

  /// 向百炼单次下发的音频时长（毫秒，默认 100ms）。
  final int realtimeFrameMs;

  /// 是否开启心跳。
  final bool realtimeHeartbeat;

  /// 最大句间静音（毫秒）。
  final int realtimeMaxSilenceMs;

  /// 语义标点。
  final bool realtimeSemanticPunct;

  /// 环形缓冲覆盖时长（毫秒，供断线回放）。
  final int realtimeRingMs;

  /// 实时任务最大重启次数。
  final int realtimeMaxRestart;

  // ── 离线文件转写（filetrans） ──

  /// 终稿模型名。
  final String filetransModel;

  /// HTTP base（空 = 按地域/Workspace 推导）。
  final String bailianHttpBase;

  /// 语言提示。
  final List<String> filetransLanguageHints;

  /// 说话人分离开关（字段名 `diarization_enabled`）。
  final bool filetransDiarization;

  /// 轮询间隔（毫秒，默认 3000 —— 架构文档 T04 规定 3s）。
  final int filetransPollIntervalMs;

  /// 轮询超时（毫秒）。
  final int filetransTimeoutMs;

  /// 失败重试次数。
  final int filetransMaxRetry;

  // ── 临时上传 ──

  /// 上传超时（毫秒）。
  final int uploadTimeoutMs;

  /// 上传重试次数。
  final int uploadMaxRetry;

  /// 单文件大小上限（MB）。
  final int uploadMaxMb;

  // ── 导入音视频（IMPORT-PIPELINE-DESIGN §7；独立于录音 WAV 的 uploadMaxMb）──

  /// 导入单文件大小上限（MB，默认 2048 = 2GB，跟随百炼 filetrans 官方上限）。
  ///
  /// 刻意**不复用** [uploadMaxMb]（200MB）：那是录音 WAV 的既有上限，
  /// 导入场景按官方 2GB 独立放宽，互不影响。
  final int importMaxMb;

  /// 导入音频时长硬上限（小时，默认 12，官方 filetrans 限制）。
  final int importMaxDurationHours;

  /// 说话人分离建议时长上限（小时，默认 2；超出仅软提示，不阻断）。
  final int importDiarizationSoftLimitHours;

  // ── HTTP 通用 ──

  /// 全局 HTTP 超时（毫秒）。
  final int httpTimeoutMs;

  // ── 纪要生成（OpenAI 兼容） ──

  /// LLM 模型名。
  final String llmModel;

  /// 是否开启思考模式（默认 false，避免首字延迟与 token 挤占）。
  final bool llmEnableThinking;

  /// OpenAI 兼容 base URL。
  final String llmBaseUrl;

  /// 温度。
  final double llmTemperature;

  /// 单次输出上限（token）。
  final int llmMaxTokens;

  /// LLM 聊天路径墙钟超时（毫秒）。
  final int llmTimeoutMs;

  /// LLM 重试次数。
  final int llmMaxRetry;

  /// 纪要总结策略 id。
  final String summaryStrategy;

  // ── 说话人聚类 ──

  /// 聚类阈值（默认 0.75）。
  final double speakerThreshold;

  // ── 服务与存储 ──

  /// 日志级别。
  final String logLevel;

  /// 固定采样率（16000）。
  final int sampleRate;

  /// 音频归档方式：`local`（默认） | `cos`（仅预留接口）。
  final String audioStorage;

  /// 是否挂载 debug-only 的本地 HTTP 适配层。
  final bool enableLocalHttp;

  /// 本地 HTTP 调试端口。
  final int localHttpPort;

  /// 是否使用 Mock 引擎。
  final bool useMockEngine;

  /// 应用版本号。
  final String version;

  /// 构建戳（构建时以 `--dart-define=BUILD_STAMP=...` 注入，如 `0925-2240/7aa4281`）。
  ///
  /// 用于「手机 App 与下载页是否同一构建」的目视核对；未注入为空串。
  final String buildStamp;

  /// 默认的运行时配置（未指定的键取原 Node 版默认值）。
  ///
  /// 优先使用 `--dart-define` 注入的值；未注入时回落到默认值。
  factory AppConfig.defaults() {
    final RealtimeModelResolution realtime = _resolveRealtimeModel();
    return AppConfig(
      engineProvider: _readString('ENGINE_PROVIDER', 'bailian'),
      dashscopeApiKey: Secrets.dashscopeApiKey.isNotEmpty
          ? Secrets.dashscopeApiKey
          : _readString('DASHSCOPE_API_KEY', ''),
      dashscopeWorkspaceId: Secrets.dashscopeWorkspaceId.isNotEmpty
          ? Secrets.dashscopeWorkspaceId
          : _readString('DASHSCOPE_WORKSPACE_ID', ''),
      bailianRegion: _readString('BAILIAN_REGION', 'cn-beijing'),
      realtimeModel: realtime.effective,
      realtimeWsUrl: _readString('BAILIAN_REALTIME_WS_URL', ''),
      realtimeSampleRate: _readInt('BAILIAN_REALTIME_SAMPLE_RATE', 16000),
      realtimeFrameMs: _readInt('BAILIAN_REALTIME_FRAME_MS', 100),
      realtimeHeartbeat: _readBool('BAILIAN_REALTIME_HEARTBEAT', true),
      realtimeMaxSilenceMs: _readInt('BAILIAN_REALTIME_MAX_SILENCE_MS', 1300),
      realtimeSemanticPunct: _readBool('BAILIAN_REALTIME_SEMANTIC_PUNCT', true),
      realtimeRingMs: _readInt('REALTIME_RING_MS', 30000),
      realtimeMaxRestart: _readInt('REALTIME_MAX_RESTART', 3),
      filetransModel: _readString('BAILIAN_FILETRANS_MODEL', 'qwen-audio-3.1-asr-flash-filetrans'),
      bailianHttpBase: _readString('BAILIAN_HTTP_BASE', ''),
      filetransLanguageHints: const <String>['zh', 'en'],
      filetransDiarization: _readBool('BAILIAN_FILETRANS_DIARIZATION', true),
      filetransPollIntervalMs: _readInt('FILETRANS_POLL_INTERVAL_MS', 3000),
      filetransTimeoutMs: _readInt('FILETRANS_TIMEOUT_MS', 1800000),
      filetransMaxRetry: _readInt('FILETRANS_MAX_RETRY', 2),
      uploadTimeoutMs: _readInt('UPLOAD_TIMEOUT_MS', 120000),
      uploadMaxRetry: _readInt('UPLOAD_MAX_RETRY', 3),
      uploadMaxMb: _readInt('UPLOAD_MAX_MB', 200),
      importMaxMb: _readInt('IMPORT_MAX_MB', 2048),
      importMaxDurationHours: _readInt('IMPORT_MAX_DURATION_HOURS', 12),
      importDiarizationSoftLimitHours: _readInt('IMPORT_DIARIZATION_SOFT_LIMIT_HOURS', 2),
      httpTimeoutMs: _readInt('HTTP_TIMEOUT_MS', 30000),
      llmModel: _readString('BAILIAN_LLM_MODEL', 'qwen3.7-plus'),
      llmEnableThinking: _readBool('BAILIAN_LLM_ENABLE_THINKING', false),
      llmBaseUrl: _readString(
        'BAILIAN_LLM_BASE_URL',
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      llmTemperature: _readDouble('LLM_TEMPERATURE', 0.3),
      llmMaxTokens: _readInt('LLM_MAX_TOKENS', 8192),
      llmTimeoutMs: _readInt('LLM_TIMEOUT_MS', 180000),
      llmMaxRetry: _readInt('LLM_MAX_RETRY', 2),
      summaryStrategy: _readString('SUMMARY_STRATEGY', 'knowledge-extract'),
      speakerThreshold: _readDouble('SPEAKER_THRESHOLD', 0.75),
      logLevel: Secrets.logLevel.isNotEmpty ? Secrets.logLevel : _readString('LOG_LEVEL', 'info'),
      sampleRate: 16000,
      audioStorage: _readString('AUDIO_STORAGE', 'local'),
      enableLocalHttp: Secrets.enableLocalHttp,
      localHttpPort: Secrets.localHttpPort,
      useMockEngine: Secrets.useMockEngine || _readString('ENGINE_PROVIDER', 'bailian') == 'mock',
      version: _readString('SMART_MINUTES_VERSION', '1.0.0'),
      buildStamp: Secrets.buildStamp,
    );
  }

  /// 启动期强校验：返回所有配置问题（空列表 = 通过）。
  ///
  /// 与主理人决策一致：`mock` 引擎仅用于离线自测，运行时若缺 Key 必须**显式报错**，
  /// 不静默回落。COS 归档（`audioStorage=cos`）当前**不实现**，故一律报错提示。
  List<String> validate() {
    final List<String> errors = <String>[];
    if (!<String>['bailian', 'mock'].contains(engineProvider)) {
      errors.add('[配置错误] ENGINE_PROVIDER="$engineProvider" 不是合法取值。允许值：bailian | mock。');
    }
    if (engineProvider == 'bailian' && dashscopeApiKey.isEmpty) {
      errors.add('[配置缺失] 缺少 DASHSCOPE_API_KEY。请用 --dart-define=DASHSCOPE_API_KEY=sk-xxx 注入。');
    }
    if (audioStorage != 'local' && audioStorage != 'cos') {
      errors.add('[配置错误] AUDIO_STORAGE="$audioStorage" 不是合法取值。允许值：local | cos。');
    }
    if (audioStorage == 'cos') {
      errors.add('[配置提示] AUDIO_STORAGE=cos 当前未实现（COS 只留接口），请改用 local。');
    }
    if (realtimeSampleRate <= 0) {
      errors.add('[配置错误] BAILIAN_REALTIME_SAMPLE_RATE 必须为正整数。');
    }
    return errors;
  }

  /// 应用日志级别到全局日志器。
  void applyLogLevel() => setLogLevel(logLevel);

  /// 一行汇总**实际生效**的全部模型名（启动日志 / 自检面板 / 诊断导出用）。
  ///
  /// 目的：让"模型名写错"这类问题在启动那一刻就**肉眼可见**，
  /// 不必等实时零句子才发现。
  String describeModels() =>
      'engine=$engineProvider realtime=$realtimeModel '
      'filetrans=$filetransModel llm=$llmModel';

  /// 解析并收敛实时模型名（不在白名单 → 回退 + 醒目告警）。
  static RealtimeModelResolution _resolveRealtimeModel() {
    final RealtimeModelResolution resolution = resolveRealtimeModel(
      _readString('BAILIAN_REALTIME_MODEL', kDefaultRealtimeModel),
    );
    if (resolution.fellBack) {
      logWarn(
        'config',
        '实时模型名不在白名单内，已自动回退 —— 原值=${resolution.original} '
        '采用值=${resolution.effective}（白名单 ${kKnownRealtimeModels.length} 个，'
        '含 $kDefaultRealtimeModel）',
      );
    }
    return resolution;
  }

  /// 读取字符串型 `--dart-define` 值。
  static String _readString(String key, String fallback) {
    final String raw = String.fromEnvironment(key);
    return raw.isEmpty ? fallback : raw;
  }

  /// 读取整型 `--dart-define` 值。
  static int _readInt(String key, int fallback) {
    final String raw = String.fromEnvironment(key);
    if (raw.isEmpty) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  /// 读取布尔型 `--dart-define` 值（`true/1/yes/on` 为真）。
  static bool _readBool(String key, bool fallback) {
    final String raw = String.fromEnvironment(key);
    if (raw.isEmpty) return fallback;
    final String value = raw.toLowerCase();
    if (<String>['true', '1', 'yes', 'on'].contains(value)) return true;
    if (<String>['false', '0', 'no', 'off'].contains(value)) return false;
    return fallback;
  }

  /// 读取浮点型 `--dart-define` 值。
  static double _readDouble(String key, double fallback) {
    final String raw = String.fromEnvironment(key);
    if (raw.isEmpty) return fallback;
    return double.tryParse(raw) ?? fallback;
  }
}
