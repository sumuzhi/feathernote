/// UI 层展示格式化工具（纯函数，便于单测）。
///
/// 与后端 `core/ids.dart` 的 `formatMs` / `formatDateTimeCn` 区分：
/// 后者用于日志与落库展示，这里专供界面文案（中文、口语化）。
library;

import '../../domain/enums.dart';

/// 会议状态 → 中文文案。
String meetingStatusLabel(MeetingStatus status) => switch (status) {
  MeetingStatus.recording => '录音中',
  MeetingStatus.stopped => '已停止',
  MeetingStatus.minutesReady => '纪要已就绪',
};

/// 终稿状态 → 中文文案。
String finalizeStatusLabel(FinalizeStatus status) => switch (status) {
  FinalizeStatus.none => '未触发',
  FinalizeStatus.pending => '生成中',
  FinalizeStatus.done => '已完成',
  FinalizeStatus.failed => '失败',
};

/// 逐字稿来源 → 中文文案。
String transcriptSourceLabel(TranscriptSource source) => switch (source) {
  TranscriptSource.realtime => '实时转写',
  TranscriptSource.filetrans => '终稿转写（含说话人分离）',
};

/// 音频归档状态 → 中文文案。
String audioStatusLabel(AudioStatus status) => switch (status) {
  AudioStatus.none => '未归档',
  AudioStatus.uploading => '归档中',
  AudioStatus.done => '已归档',
  AudioStatus.failed => '归档失败',
};

/// 把毫秒格式化为计时器文案：`12:34`，超过 1 小时为 `1:02:33`。
String formatClock(int milliseconds) {
  final int totalSeconds = (milliseconds < 0 ? 0 : milliseconds) ~/ 1000;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$mm:$ss';
}

/// 把毫秒格式化为中文时长：`3 小时 12 分钟` / `32 分钟` / `低于 1 分钟`。
String formatDurationCn(int milliseconds) {
  final int totalMinutes = (milliseconds < 0 ? 0 : milliseconds) ~/ 60000;
  if (totalMinutes <= 0) return '低于 1 分钟';
  final int hours = totalMinutes ~/ 60;
  final int minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return '$hours 小时 $minutes 分钟';
  if (hours > 0) return '$hours 小时';
  return '$minutes 分钟';
}

/// 千分位数字：`1860` → `1,860`。
String formatThousands(int value) {
  final String digits = value.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

/// 字数文案：`1,860 字`。
String formatCharCount(int count) => '${formatThousands(count)} 字';

/// 人数文案：`3 人`。
String formatPeople(int count) => '$count 人';

/// 说话人文案：`3 位说话人`。
String formatSpeakerCount(int count) => '$count 位说话人';

/// 时刻：`09:12`（24 小时制，补零）。
String formatHm(DateTime time) {
  final String h = time.hour.toString().padLeft(2, '0');
  final String m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// 日期：`09-18`。
String formatMonthDay(DateTime time) {
  final String m = time.month.toString().padLeft(2, '0');
  final String d = time.day.toString().padLeft(2, '0');
  return '$m-$d';
}

/// 相对日：`今天` / `昨天` / `09-18`。
String formatDayLabel(DateTime time, {DateTime? now}) {
  final DateTime today = _dayStart(now ?? DateTime.now());
  final DateTime target = _dayStart(time);
  final int diffDays = today.difference(target).inDays;
  if (diffDays == 0) return '今天';
  if (diffDays == 1) return '昨天';
  return formatMonthDay(time);
}

/// 日期 + 时刻：`今天 09:12` / `09-18 09:12`。
String formatDayTime(DateTime time, {DateTime? now}) =>
    '${formatDayLabel(time, now: now)} ${formatHm(time)}';

/// 月日 + 时刻（无相对日）：`09-18 09:12`。
String formatMonthDayTime(DateTime time) => '${formatMonthDay(time)} ${formatHm(time)}';

/// 历史卡片元信息行：`32 分钟 · 今天 09:12`。
String formatHistoryMeta({
  required int durationMs,
  required DateTime createdAt,
  DateTime? now,
}) => '${formatDurationCn(durationMs)} · ${formatDayTime(createdAt, now: now)}';

/// 转写页信息行：`32 分钟 · 3 位说话人`。
String formatTranscriptInfo({required int durationMs, required int speakerCount}) =>
    '${formatDurationCn(durationMs)} · ${formatSpeakerCount(speakerCount)}';

/// 按时段问候：`早上好` / `中午好` / `下午好` / `晚上好`。
String greetingFor(DateTime time) {
  final int hour = time.hour;
  if (hour < 6) return '凌晨好';
  if (hour < 11) return '早上好';
  if (hour < 14) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

/// 前缀 `发言人` 的兜底显示名（与后端 `speakers.name` 默认值一致）。
String speakerLabel(int ordainal1Based) => '发言人$ordainal1Based';

DateTime _dayStart(DateTime time) => DateTime(time.year, time.month, time.day);
