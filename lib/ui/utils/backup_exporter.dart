/// 数据备份导出（用户要求：「设置 → 数据库」点击导出，内容经主理人确认）。
///
/// 备份 = **含音频全量 ZIP**，并按每条数据分类（用户要求：每场会议单独一个
/// md，不把多个总结写进同一个文档）：
/// ```
/// feathernote-backup-<stamp>.zip
///   ├─ backup.json          —— 全量结构化数据（会议元信息 + 逐字稿 + AI 纪要），
///                              未来「数据恢复」功能的数据源；
///   ├─ minutes/<序号>-<标题>.md —— 每场会议单独一个 Markdown；
///   └─ audio/<key>          —— 各会议本地音频原文件（存在才打包）。
/// ```
///
/// ## 卡死修复（2026-10-10）
/// 原实现把所有重活在**主（UI）线程**完成：一次性 `JsonEncoder` 把全量数据编码成
/// 一个巨大字符串 + 把整包 ZIP 读进内存（`readAsBytes`）→ 数据量大时 UI 直接冻死。
/// 现改造为：
/// 1. **重活搬进后台 isolate**：序列化 + 流式写 `backup.json` + 流式打 ZIP 全部在
///    独立 isolate 执行，UI 全程不阻塞；
/// 2. **流式写 backup.json**：逐场会议增量 `IOSink` 写出，不再持有「全量编码字符串」
///    那份额外内存（峰值约减半）；
/// 3. **平台落盘留在主线程**：MediaStore / SAF 是插件通道，必须在主 isolate；
///    默认 `appDownload` 走 MediaStore 原生拷贝（不在 Dart 堆里读整包），
///    SAF（用户显式「每次选择」）保留 `readAsBytes`（用户主动选择，非默认路径）；
/// 4. **前台服务保活**：导出期间 `acquire('export')`，切后台 / 锁屏不被系统回收；
/// 5. **进度 + 取消**：`onProgress` 回调驱动「数据库」行进度条；`BackupCancelToken`
///    经控制端口通知 isolate 中止并清理临时文件。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import 'export_destination.dart';
import 'exporter.dart'
    show
        ExportCancelledException,
        kExportLocationAppDocs,
        sanitizeFileName,
        saveToPublicDownload;

/// isolate → 主线程消息：进度。
const String _kProgress = 'progress';

/// isolate → 主线程消息：完成（附 zip 路径）。
const String _kDone = 'done';

/// isolate → 主线程消息：失败（附错误信息）。
const String _kError = 'error';

/// 取消哨兵：isolate 内的 [_CancelledException] 以该标记跨 isolate 传递
/// （异常对象 stringify 后类型信息丢失，主线程无法区分「用户取消」与真失败）。
const String _kCancelledSentinel = '__cancelled__';

/// 进度回调（主线程，可安全 `setState`）。
typedef BackupProgressCallback = void Function(double fraction, String phase);

/// 取消令牌：调用方与 `exportBackup` 共享同一实例；
/// 用户在 UI 上点「取消」时调用 [cancel]，经控制端口通知后台 isolate 中止。
class BackupCancelToken {
  SendPort? _controlSendPort;
  bool _requested = false;

  /// 由 `exportBackup` 在收到 isolate 控制端口后绑定（导出中途取消也能即时生效）。
  void _bind(SendPort port) {
    _controlSendPort = port;
    if (_requested) port.send('cancel');
  }

  /// 请求取消（幂等）。
  void cancel() {
    _requested = true;
    _controlSendPort?.send('cancel');
  }
}

/// isolate 内抛出的「用户取消」信号（不污染调用方的业务异常）。
class _CancelledException implements Exception {
  const _CancelledException();
}

/// 构建 backup.json 内容（纯函数，便于单测）。
Map<String, dynamic> buildBackupJson({
  required List<Meeting> meetings,
  int? schemaVersion,
  required DateTime exportedAt,
}) {
  return <String, dynamic>{
    'app': 'feathernote',
    'kind': 'backup',
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'count': meetings.length,
    'meetings': <Map<String, dynamic>>[
      for (final Meeting m in meetings) _meetingJson(m),
    ],
  };
}

Map<String, dynamic> _meetingJson(Meeting m) => <String, dynamic>{
      'id': m.id,
      'title': m.title,
      'createdAt': m.createdAt.toIso8601String(),
      'durationMs': m.durationMs,
      'sampleRate': m.sampleRate,
      'speakerCount': m.speakerCount,
      'status': m.status.value,
      'source': m.source.value,
      'finalizeStatus': m.finalizeStatus.value,
      'transcriptSource': m.transcriptSource.value,
      'audioStatus': m.audioStatus.value,
      'audioKey': m.audioKey,
      'audioBytes': m.audioBytes,
      'audioError': m.audioError,
      'minutesPartial': m.minutesPartial,
      'minutesMd': m.minutesMd,
      'minutesError': m.minutesError,
      'finalizeError': m.finalizeError,
      'importStatus': m.importStatus.value,
      'importError': m.importError,
      'importTaskId': m.importTaskId,
      'importMetaJson': m.importMetaJson,
      'segments': <Map<String, dynamic>>[
        for (final TranscriptSegment s in m.segments)
          <String, dynamic>{
            'meetingId': s.meetingId,
            'segmentId': s.segmentId,
            'ordinal': s.ordinal,
            'speakerId': s.speakerId,
            'speakerName': s.speakerName,
            'text': s.text,
            'startTime': s.startTime,
            'endTime': s.endTime,
            'confidence': s.confidence,
            'seqStart': s.seqStart,
            'seqEnd': s.seqEnd,
          },
      ],
      'speakers': <Map<String, dynamic>>[
        for (final Speaker sp in m.speakers)
          <String, dynamic>{
            'meetingId': sp.meetingId,
            'speakerId': sp.speakerId,
            'name': sp.name,
            'colorIndex': sp.colorIndex,
            'firstSeenMs': sp.firstSeenMs,
          },
      ],
    };

/// 构建单场会议的人读 Markdown（纯函数，便于单测）。
///
/// 用户要求：导出按每条数据分类——每场会议**单独一个 md 文件**，
/// 不再把多个总结写进同一个文档。
String buildMeetingMarkdown(Meeting meeting) {
  final StringBuffer out = StringBuffer();
  out.writeln('# ${meeting.title}');
  out.writeln();
  out.writeln('- 创建时间：${meeting.createdAt.toIso8601String()}');
  out.writeln('- 时长：${meeting.durationMs} ms · 说话人：${meeting.speakerCount}');
  out.writeln('- 来源：${meeting.source.value} · 状态：${meeting.status.value}');
  out.writeln();
  if ((meeting.minutesMd ?? '').trim().isNotEmpty) {
    out.writeln('## AI 纪要');
    out.writeln();
    out.writeln(meeting.minutesMd!.trimRight());
    out.writeln();
  }
  if (meeting.segments.isNotEmpty) {
    out.writeln('## 逐字稿（${meeting.segments.length} 段）');
    out.writeln();
    for (final TranscriptSegment s in meeting.segments) {
      final String name = (s.speakerName == null || s.speakerName!.isEmpty)
          ? s.speakerId
          : s.speakerName!;
      out.writeln('- **[$name · ${s.startTime}ms]** ${s.text}');
    }
    out.writeln();
  }
  return out.toString();
}

/// 从 backup.json 的会议 Map 重建 Markdown（isolate 内 / 单测使用，避免跨
/// isolate 传 [Meeting] 对象）。
///
/// 与 [buildMeetingMarkdown] 输出逐字符一致（见单测）。
String meetingMapToMarkdown(Map<String, dynamic> m) {
  final StringBuffer out = StringBuffer();
  out.writeln('# ${m['title']}');
  out.writeln();
  out.writeln('- 创建时间：${m['createdAt']}');
  out.writeln('- 时长：${m['durationMs']} ms · 说话人：${m['speakerCount']}');
  out.writeln('- 来源：${m['source']} · 状态：${m['status']}');
  out.writeln();
  final String? minutesMd = m['minutesMd'] as String?;
  if ((minutesMd ?? '').trim().isNotEmpty) {
    out.writeln('## AI 纪要');
    out.writeln();
    out.writeln(minutesMd!.trimRight());
    out.writeln();
  }
  final List<dynamic> segments =
      (m['segments'] as List<dynamic>?) ?? const <dynamic>[];
  if (segments.isNotEmpty) {
    out.writeln('## 逐字稿（${segments.length} 段）');
    out.writeln();
    for (final dynamic s in segments) {
      final Map<String, dynamic> seg = s as Map<String, dynamic>;
      final String? speakerName = seg['speakerName'] as String?;
      final String name = (speakerName == null || speakerName.isEmpty)
          ? (seg['speakerId'] as String)
          : speakerName;
      out.writeln(
        '- **[$name · ${seg['startTime']}ms]** ${seg['text']}',
      );
    }
    out.writeln();
  }
  return out.toString();
}

/// JSON 字面量编码（顶层标量字段用）。
String _json(Object? value) => json.encode(value);

/// 流式写 backup.json：逐场会议增量写出，**不持有全量编码字符串**，压住内存峰值。
///
/// 语义与 `JsonEncoder.withIndent('  ').convert(root)` 完全一致（解码后相等），
/// 仅排版更紧凑（内层对象单行）。[isCancelled] 在每场会议之间被检查，命中即中止。
///
/// 暴露为公开函数以便单测直接验证「流式 == 全量编码」等价性与取消行为。
Future<void> writeBackupJsonStreaming(
  String path,
  Map<String, dynamic> root,
  BackupProgressCallback onProgress,
  bool Function() isCancelled,
) async {
  final List<dynamic> meetings =
      (root['meetings'] as List<dynamic>?) ?? const <dynamic>[];
  final IOSink sink = File(path).openWrite();
  try {
    sink.write('{\n');
    sink.write('  "app": ${_json(root['app'])},\n');
    sink.write('  "kind": ${_json(root['kind'])},\n');
    sink.write('  "schemaVersion": ${_json(root['schemaVersion'])},\n');
    sink.write('  "exportedAt": ${_json(root['exportedAt'])},\n');
    sink.write('  "count": ${meetings.length},\n');
    sink.write('  "meetings": [\n');
    for (int i = 0; i < meetings.length; i++) {
      if (isCancelled()) throw const _CancelledException();
      // 内层对象用紧凑编码（无缩进），逐场写出后释放该场字符串。
      sink.write('    ${json.encode(meetings[i])}');
      if (i < meetings.length - 1) {
        sink.write(',\n');
      } else {
        sink.write('\n');
      }
      if (meetings.isNotEmpty) {
        onProgress((i + 1) / meetings.length * 0.4, '正在序列化会议数据');
      }
    }
    sink.write('  ]\n');
    sink.write('}\n');
  } finally {
    await sink.flush();
    await sink.close();
  }
}

/// 在本地临时目录构建备份 ZIP（**不含平台落盘**）。
///
/// 纯函数、无插件依赖，可在后台 isolate 中运行；也便于单测直接调用。
/// 三步全部流式，ZIP 与音频不整体驻留内存：
/// 1. 流式写 `backup.json`；
/// 2. 每场会议一个 md；
/// 3. `ZipFileEncoder` 流式打包（音频从磁盘逐文件进 zip）。
///
/// 暴露为公开函数以便单测验证 ZIP 产物与取消清理。
Future<String> buildLocalBackupZip({
  required Map<String, dynamic> backupMap,
  required List<String?> audioPaths,
  required String workDirPath,
  required String zipPath,
  required BackupProgressCallback onProgress,
  required bool Function() isCancelled,
}) async {
  final Directory workDir = Directory(workDirPath);
  final Directory minutesDir = Directory(p.join(workDir.path, 'minutes'));
  if (!minutesDir.existsSync()) await minutesDir.create(recursive: true);

  final File jsonFile = File(p.join(workDir.path, 'backup.json'));
  await writeBackupJsonStreaming(
    jsonFile.path,
    backupMap,
    onProgress,
    isCancelled,
  );

  final List<dynamic> meetings =
      (backupMap['meetings'] as List<dynamic>?) ?? const <dynamic>[];
  final List<(String, String)> mdRel = <(String, String)>[];
  for (int i = 0; i < meetings.length; i++) {
    if (isCancelled()) throw const _CancelledException();
    final Map<String, dynamic> m = meetings[i] as Map<String, dynamic>;
    final String title = (m['title'] as String?) ?? 'meeting';
    final String fileName = '${i + 1}-${sanitizeFileName(title)}.md';
    final File mdFile = File(p.join(minutesDir.path, fileName));
    await mdFile.writeAsString(meetingMapToMarkdown(m), flush: true);
    mdRel.add((mdFile.path, 'minutes/$fileName'));
    onProgress(0.4 + (i + 1) / (meetings.isEmpty ? 1 : meetings.length) * 0.1,
        '正在写入会议纪要文档');
  }

  final ZipFileEncoder encoder = ZipFileEncoder();
  encoder.create(zipPath);
  try {
    await encoder.addFile(jsonFile, 'backup.json');
    for (final (String filePath, String rel) in mdRel) {
      await encoder.addFile(File(filePath), rel);
    }
    final int audioCount =
        audioPaths.where((String? e) => e != null && e.isNotEmpty).length;
    int done = 0;
    for (final String? ap in audioPaths) {
      if (isCancelled()) throw const _CancelledException();
      if (ap == null || ap.isEmpty) continue;
      final File audioFile = File(ap);
      if (!audioFile.existsSync()) continue;
      final String audioName =
          'audio/${p.basenameWithoutExtension(ap)}${p.extension(ap)}';
      await encoder.addFile(audioFile, audioName);
      done++;
      onProgress(
        0.5 + 0.5 * (done / (audioCount == 0 ? 1 : audioCount)),
        '正在打包音频与文档',
      );
    }
  } finally {
    await encoder.close();
  }
  return zipPath;
}

/// 后台 isolate 入口：接收主线程派发的负载，构建本地 ZIP 并通过 [SendPort] 回报
/// 进度 / 完成 / 失败。
///
/// 进入消息：`[SendPort report, Map<String, dynamic> payload]`；
/// 首条回报是控制端口（`SendPort`），供主线程反向发送「取消」。
Future<void> _exportEntry(dynamic message) async {
  final List<dynamic> envelope = message as List<dynamic>;
  final SendPort report = envelope[0] as SendPort;
  final Map<String, dynamic> p = envelope[1] as Map<String, dynamic>;

  final ReceivePort control = ReceivePort();
  report.send(control.sendPort);

  bool cancelled = false;
  control.listen((_) {
    cancelled = true;
  });

  void onProgress(double fraction, String phase) =>
      report.send(<dynamic>[_kProgress, fraction, phase]);

  try {
    final String zipPath = await buildLocalBackupZip(
      backupMap: p['backupMap'] as Map<String, dynamic>,
      audioPaths: (p['audioPaths'] as List<dynamic>).cast<String?>(),
      workDirPath: p['workDir'] as String,
      zipPath: p['zipPath'] as String,
      onProgress: onProgress,
      isCancelled: () => cancelled,
    );
    report.send(<dynamic>[_kDone, zipPath]);
  } catch (error) {
    report.send(<dynamic>[
      _kError,
      error is _CancelledException ? _kCancelledSentinel : error.toString(),
    ]);
  } finally {
    control.close();
  }
}

/// 清理临时工作目录与临时 ZIP（导出成功落盘后 / 取消 / 失败时使用）。
void _cleanup(String workDirPath, String zipPath) {
  try {
    final Directory workDir = Directory(workDirPath);
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
  } catch (_) {
    // 临时目录清理失败不阻断主流程（下次导出用新 stamp 目录，不会无限堆积）。
  }
  try {
    final File zip = File(zipPath);
    if (zip.existsSync()) zip.deleteSync();
  } catch (_) {
    // 同上。
  }
}

/// 导出数据备份 ZIP，返回**给用户展示的保存位置**与**取消令牌**。
///
/// 重活（序列化 + 流式打 ZIP）在后台 isolate 执行，UI 不阻塞；平台落盘（MediaStore
/// / SAF）在主线程完成。返回的 [BackupCancelToken] 可交 UI 用于中途取消。
///
/// [audioPathResolver]：给定会议返回本地音频文件路径（null/文件不存在则跳过
/// 该会议的音频）；由调用方注入（`BackendApi.getAudioPath` 已区分录音/导入
/// 两种 key 约定）。
Future<({String location, BackupCancelToken handle})> exportBackup({
  required List<Meeting> meetings,
  required ExportDestination destination,
  int? schemaVersion,
  DateTime? exportedAt,
  required Future<String?> Function(Meeting meeting) audioPathResolver,
  BackupProgressCallback? onProgress,
  BackupCancelToken? cancelToken,
}) async {
  final DateTime now = exportedAt ?? DateTime.now();
  final String stamp = _stamp(now);
  final String zipName = 'feathernote-backup-$stamp';

  // 临时工作目录与 ZIP 路径（path_provider 是插件，必须主线程算好再传给 isolate）。
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory workDir =
      Directory(p.join(base.path, 'exports', 'backup-$stamp'));
  final Directory minutesDir = Directory(p.join(workDir.path, 'minutes'));
  if (!minutesDir.existsSync()) {
    await minutesDir.create(recursive: true);
  }
  final String zipPath = p.join(base.path, 'exports', '$zipName.zip');

  // 音频路径解析需经 api（主线程）。
  final List<String?> audioPaths = <String?>[];
  for (final Meeting m in meetings) {
    audioPaths.add(await audioPathResolver(m));
  }

  // 构建可跨 isolate 发送的备份 Map（纯数据，无函数/句柄）。
  final Map<String, dynamic> backupMap = buildBackupJson(
    meetings: meetings,
    schemaVersion: schemaVersion,
    exportedAt: now,
  );

  // 派发后台 isolate。
  final ReceivePort report = ReceivePort();
  final Isolate isolate = await Isolate.spawn(
    _exportEntry,
    <dynamic>[
      report.sendPort,
      <String, dynamic>{
        'backupMap': backupMap,
        'audioPaths': audioPaths,
        'workDir': workDir.path,
        'zipPath': zipPath,
        'zipName': zipName,
      },
    ],
  );

  SendPort? controlSendPort;
  Object? error;
  await for (final dynamic msg in report) {
    if (msg is SendPort) {
      controlSendPort = msg;
      cancelToken?._bind(controlSendPort);
      continue;
    }
    final List<dynamic> m = msg as List<dynamic>;
    final String kind = m[0] as String;
    if (kind == _kProgress) {
      onProgress?.call(m[1] as double, m[2] as String);
    } else if (kind == _kDone) {
      // 完成 / 失败都要 break 循环体本身。⚠️ 历史缺陷：这里曾是 switch +
      // `break`——Dart 的 break 只跳出 switch 跳不出 await for，而后台
      // isolate 发完消息即退出、没人关闭 report 端口 → 主线程在 100% 处
      // 永久挂起（真机实测「导出卡在 100%」的根因）。
      break;
    } else if (kind == _kError) {
      final Object payload = m[1] as Object;
      // 取消哨兵还原为异常对象：让调用方区分「用户取消」与真失败。
      error = payload == _kCancelledSentinel ? const _CancelledException() : payload;
      break;
    }
  }
  report.close();

  if (error != null) {
    _cleanup(workDir.path, zipPath);
    isolate.kill();
    if (error is _CancelledException) {
      throw const ExportCancelledException();
    }
    throw Exception('备份导出失败：$error');
  }

  // 平台落盘（主线程；MediaStore 原生拷贝不占 Dart 堆，SAF 用户主动选择）。
  // 大 ZIP 拷贝可达数秒，先报一阶段文案，避免 UI 停在 100% 无反馈。
  onProgress?.call(1.0, '正在保存文件');
  String location;
  if (destination == ExportDestination.askEachTime && Platform.isAndroid) {
    final Uint8List bytes = await File(zipPath).readAsBytes();
    final String? pickedPath = await FilePicker.platform.saveFile(
      fileName: '$zipName.zip',
      bytes: bytes,
    );
    if (pickedPath == null) {
      _cleanup(workDir.path, zipPath);
      isolate.kill();
      throw const ExportCancelledException();
    }
    // 已安全落盘，删除临时文件。
    _cleanup(workDir.path, zipPath);
    location = p.basename(pickedPath);
  } else if (Platform.isAndroid) {
    location = await saveToPublicDownload(
      tempFilePath: zipPath,
      fileName: '$zipName.zip',
    );
    // MediaStore 已原生拷贝，删除临时 ZIP 释放磁盘。
    _cleanup(workDir.path, zipPath);
  } else {
    // iOS 等：无公共下载目录概念，沿用旧语义仅回传标签（不删临时 ZIP，避免数据丢失）。
    location = kExportLocationAppDocs;
  }
  isolate.kill();
  return (location: location, handle: cancelToken ?? BackupCancelToken());
}

String _stamp(DateTime now) =>
    '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');
