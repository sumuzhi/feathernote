/// ID 生成与通用纯函数（移植自 `server/src/shared.js` 的 ID / 时间 / 哈希工具）。
library;

import 'dart:math';

/// 生成会议 ID：`mtg_<base36 timestamp>_<4位随机>`。
String genMeetingId([int? nowMs]) {
  return _genPrefixed('mtg', nowMs);
}

/// 生成 WS 会话 ID：`sess_<base36 timestamp>_<4位随机>`。
String genSessionId([int? nowMs]) {
  return _genPrefixed('sess', nowMs);
}

/// 拼装 `<prefix>_<base36 时间戳>_<4 位 base36 随机数>`（与原 Node 版同形）。
String _genPrefixed(String prefix, int? nowMs) {
  final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final String ts = now.toRadixString(36);
  final int rand = Random().nextInt(36 * 36 * 36 * 36); // 36^4
  final String randStr = rand.toRadixString(36).padLeft(4, '0');
  return '${prefix}_${ts}_${randStr.substring(randStr.length - 4)}';
}

/// 生成百炼任务 ID（形如 UUID v4）。
///
/// 实时 `run-task` 与 filetrans 提交都要求形如 UUID 的 `task_id`。
String genTaskId() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  // UUID version 4 + variant 10xx。
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// `genTaskId` 的语义别名（百炼任务专用）。
String dashscopeTaskId() => genTaskId();

/// 当前时间 ISO 8601（UTC），形如 `2026-09-23T07:20:01.123Z`。
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// 生成确定性字符串哈希（FNV-1a 32bit），用于 Mock 声纹种子。
int hashString(String input) {
  int hash = 0x811c9dc5;
  for (int i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    // 32 位有符号乘法（对应 JS 的 Math.imul 结果）。
    hash = _imul(hash, 0x01000193);
  }
  return hash & 0xffffffff;
}

/// 32 位整数乘法（模拟 `Math.imul`，避免 Dart int 任意精度导致结果不同）。
int _imul(int a, int b) {
  final int ah = (a >>> 16) & 0xffff;
  final int al = a & 0xffff;
  final int bh = (b >>> 16) & 0xffff;
  final int bl = b & 0xffff;
  return ((al * bl) + (((ah * bl + al * bh) << 16) >>> 0)) | 0;
}

/// 确定性伪随机数生成器（mulberry32），返回取值 [0,1) 的函数。
double Function() mulberry32(int seed) {
  int a = seed & 0xffffffff;
  return () {
    a = (a + 0x6d2b79f5) & 0xffffffff;
    int t = a;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= t + _imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296;
  };
}

/// 把整数毫秒格式化为 `mm:ss`（超过 1 小时为 `hh:mm:ss`）。
String formatMs(int ms) {
  final int total = ms < 0 ? 0 : ms;
  final int totalSec = total ~/ 1000;
  final int h = totalSec ~/ 3600;
  final int m = (totalSec % 3600) ~/ 60;
  final int s = totalSec % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '${pad(h)}:${pad(m)}:${pad(s)}' : '${pad(m)}:${pad(s)}';
}

/// 把时间格式化为中文可读日期 `YYYY-MM-DD HH:mm`（本地时区）。
String formatDateTimeCn(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} '
      '${pad(date.hour)}:${pad(date.minute)}';
}

/// 数值裁剪（非有限值返回 [min]）。
double clampDouble(double value, double min, double max) {
  if (!value.isFinite) return min;
  return value < min ? min : (value > max ? max : value);
}

/// 数值裁剪（整型）。
int clampInt(int value, int min, int max) {
  return value < min ? min : (value > max ? max : value);
}

/// 从片段结束时间列表**推导会议时长**（毫秒）：取最大值。
///
/// 用途：当客户端未显式上报 `duration_ms` 时，用片段时间轴兜底，避免时长恒为 0。
int deriveDurationMs(Iterable<num> endTimes) {
  int max = 0;
  for (final num raw in endTimes) {
    final int end = raw.isFinite ? raw.round() : 0;
    if (end > max) max = end;
  }
  return max;
}

/// 拼装百炼临时上传的 `oss://` URL（首尾斜杠规范化）。
String buildOssUrl(String uploadDir, String filename) {
  final String dir = uploadDir.replaceAll(RegExp(r'^/+|/+$'), '');
  final String name = filename.replaceAll(RegExp(r'^/+'), '');
  return 'oss://$dir/$name';
}

/// 判断是否 `oss://` 资源 URL（决定是否需注入 `X-DashScope-OssResourceResolve`）。
bool isOssUrl(String url) => url.startsWith('oss://');

/// 帧序号 → 毫秒（单帧 [frameMs] 毫秒）。
int framesToMs(int frames, {int frameMs = 20}) => frames * frameMs;

/// 毫秒 → 帧序号（向下取整）。
int framesFromMs(int ms, {int frameMs = 20}) => frameMs > 0 ? ms ~/ frameMs : 0;
