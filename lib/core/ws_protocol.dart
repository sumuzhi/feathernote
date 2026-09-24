/// WS 消息类型 / 协议级错误码 / 终稿与逐字稿来源枚举（移植自 `server/src/shared.js:64-125`）。
///
/// 方案 B 虽以「进程内调用」为主（无 WS 传输层），但这些常量仍被
/// debug-only 的 `LocalHttpServer` 适配层与原协议文档对照使用，故逐字保留。
library;

/// WS 文本消息类型（与原 Node 版契约一致）。
abstract final class WsType {
  /// 客户端握手。
  static const String hello = 'hello';

  /// 服务端握手确认。
  static const String helloAck = 'hello_ack';

  /// 开始会议。
  static const String startMeeting = 'start_meeting';

  /// 会议已建立。
  static const String meetingStarted = 'meeting_started';

  /// 断线重连探测。
  static const String resumeProbe = 'resume_probe';

  /// 重连状态。
  static const String resumeState = 'resume_state';

  /// 补包开始。
  static const String resumeBegin = 'resume_begin';

  /// 补包结束。
  static const String resumeEnd = 'resume_end';

  /// 补包结束确认。
  static const String resumeEndAck = 'resume_end_ack';

  /// 通用确认。
  static const String ack = 'ack';

  /// 逐字稿增量。
  static const String transcript = 'transcript';

  /// 会后终稿**全量替换**逐字稿。
  static const String transcriptReplace = 'transcript_replace';

  /// 说话人表更新。
  static const String speakerUpdate = 'speaker_update';

  /// 会议已停止。
  static const String meetingStopped = 'meeting_stopped';

  /// 说话人改名。
  static const String speakerRename = 'speaker_rename';

  /// 心跳。
  static const String ping = 'ping';

  /// 心跳回应。
  static const String pong = 'pong';

  /// 错误。
  static const String error = 'error';
}

/// WS 协议级错误码。
abstract final class WsError {
  /// 协议错误（非法帧 / 非法消息）。
  static const String protocol = 'E_PROTOCOL';

  /// 会话错误（未知 sessionId）。
  static const String session = 'E_SESSION';

  /// 引擎错误。
  static const String engine = 'E_ENGINE';

  /// 音频帧错误（长度不足 / 解析失败）。
  static const String audio = 'E_AUDIO';
}

/// 单帧时长（毫秒）。
const int kFrameMs = 20;

/// 单帧样本数（16kHz × 20ms）。
const int kFrameSamples = 320;

/// 单帧 PCM 字节数（16bit 单声道）。
const int kFrameBytes = kFrameSamples * 2;

/// 二进制帧固定头部长度：flag(1) + seq(4) + start_ms(4)。
const int kFrameHeaderBytes = 9;

/// 百炼任务终态（filetrans）。
abstract final class TaskStatus {
  /// 排队中。
  static const String pending = 'PENDING';

  /// 运行中。
  static const String running = 'RUNNING';

  /// 成功。
  static const String succeeded = 'SUCCEEDED';

  /// 失败。
  static const String failed = 'FAILED';

  /// 轮询超时（本地定义，非服务端状态）。
  static const String timeout = 'TIMEOUT';
}

/// 归一化任务状态到 `PENDING | RUNNING | SUCCEEDED | FAILED`。
String normalizeTaskStatus(String status) {
  final String value = status.toUpperCase();
  if (value.contains('SUCCEED')) return TaskStatus.succeeded;
  if (value.contains('FAIL')) return TaskStatus.failed;
  if (value.contains('RUNNING')) return TaskStatus.running;
  return TaskStatus.pending;
}
