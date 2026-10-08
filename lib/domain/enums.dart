/// 领域枚举：会议状态 / 来源 / 终稿状态 / 逐字稿来源 / 音频归档状态。
///
/// 取值与原 SQLite schema 的 `CHECK` 约束逐字一致。
library;

/// 会议状态。
enum MeetingStatus {
  /// 录音中。
  recording('recording'),

  /// 已停止（终稿可能仍在处理）。
  stopped('stopped'),

  /// 纪要已就绪。
  minutesReady('minutes_ready');

  /// 构造会议状态。
  const MeetingStatus(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [recording]。
  static MeetingStatus fromValue(String value) {
    for (final MeetingStatus status in MeetingStatus.values) {
      if (status.value == value) return status;
    }
    return MeetingStatus.recording;
  }
}

/// 会议来源。
enum MeetingSource {
  /// 麦克风实时采集。
  microphone('microphone'),

  /// 上传音频。
  upload('upload'),

  /// 导入音视频（本地上传文件转写）。
  imported('imported');

  /// 构造会议来源。
  const MeetingSource(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [microphone]。
  static MeetingSource fromValue(String value) {
    for (final MeetingSource source in MeetingSource.values) {
      if (source.value == value) return source;
    }
    return MeetingSource.microphone;
  }
}

/// 终稿转写状态。
enum FinalizeStatus {
  /// 未启动。
  none('none'),

  /// 处理中。
  pending('pending'),

  /// 已完成。
  done('done'),

  /// 已失败。
  failed('failed');

  /// 构造终稿状态。
  const FinalizeStatus(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [none]。
  static FinalizeStatus fromValue(String value) {
    for (final FinalizeStatus status in FinalizeStatus.values) {
      if (status.value == value) return status;
    }
    return FinalizeStatus.none;
  }
}

/// 逐字稿来源。
enum TranscriptSource {
  /// 实时流式。
  realtime('realtime'),

  /// 会后终稿。
  filetrans('filetrans');

  /// 构造逐字稿来源。
  const TranscriptSource(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [realtime]。
  static TranscriptSource fromValue(String value) {
    for (final TranscriptSource source in TranscriptSource.values) {
      if (source.value == value) return source;
    }
    return TranscriptSource.realtime;
  }
}

/// 音频归档状态。
enum AudioStatus {
  /// 无音频。
  none('none'),

  /// 上传中。
  uploading('uploading'),

  /// 已归档。
  done('done'),

  /// 归档失败。
  failed('failed');

  /// 构造音频状态。
  const AudioStatus(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [none]。
  static AudioStatus fromValue(String value) {
    for (final AudioStatus status in AudioStatus.values) {
      if (status.value == value) return status;
    }
    return AudioStatus.none;
  }
}

/// 导入处理状态机（落库 `meetings.import_status`；SSOT：IMPORT-PIPELINE-DESIGN §4）。
///
/// 状态转移：
/// `import_pending → (extracting →)? transcribing → minutes → done`，
/// 任意一步失败 / 用户取消 → `failed`（`meetings.import_error` 记录步骤 + 原因）。
enum ImportStatus {
  /// 非导入会议（录音会议恒为 none）。
  none('none'),

  /// step1：复制原文件到沙箱 + 流式上传（音频直传亦在此步）。
  importPending('import_pending'),

  /// step2：视频分离音轨（音频场景自动跳过此步）。
  extracting('extracting'),

  /// step3：filetrans 转写（FinalizePoller）。
  transcribing('transcribing'),

  /// step4：纪要生成（MinutesService）。
  minutes('minutes'),

  /// 完成。
  done('done'),

  /// 失败 / 取消（可重试）。
  failed('failed');

  /// 构造导入状态。
  const ImportStatus(this.value);

  /// 落库取值。
  final String value;

  /// 由落库字符串解析，未命中返回 [none]。
  static ImportStatus fromValue(String value) {
    for (final ImportStatus status in ImportStatus.values) {
      if (status.value == value) return status;
    }
    return ImportStatus.none;
  }
}
