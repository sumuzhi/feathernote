/// 数据备份导出（用户要求：「设置 → 数据库」点击导出，内容经主理人确认）。
///
/// 备份 = **含音频全量 ZIP**：
/// ```
/// feathernote-backup-<stamp>.zip
///   ├─ backup.json     —— 全量结构化数据（会议元信息 + 逐字稿 + AI 纪要），
///                          未来「数据恢复」功能的数据源；
///   ├─ summary.md      —— 人读 Markdown 汇总（每场会议一节）；
///   └─ audio/<key>     —— 各会议本地音频原文件（存在才打包）。
/// ```
/// 内存策略：`backup.json` / `summary.md` 先落临时目录，音频用
/// `ZipFileEncoder` **流式**从磁盘进 zip——任何会议数量/音频体积下 zip
/// 都不整体驻留内存。落位逻辑与纪要导出一致（MediaStore 公共 Download /
/// SAF 另存为 / iOS 分享面板）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:media_store_plus/media_store_plus.dart'
    show MediaStore, SaveInfo, DirType, DirName;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import 'export_destination.dart';
import 'exporter.dart' show ExportCancelledException;

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

/// 构建人读 Markdown 汇总（纯函数，便于单测）。
String buildBackupMarkdown({
  required List<Meeting> meetings,
  required DateTime exportedAt,
}) {
  final StringBuffer out = StringBuffer();
  out.writeln('# 声羽 FeatherNote 数据备份');
  out.writeln();
  out.writeln('- 导出时间：${exportedAt.toIso8601String()}');
  out.writeln('- 会议数量：${meetings.length}');
  out.writeln();
  for (final Meeting m in meetings) {
    out.writeln('---');
    out.writeln();
    out.writeln('## ${m.title}');
    out.writeln();
    out.writeln('- 创建时间：${m.createdAt.toIso8601String()}');
    out.writeln('- 时长：${m.durationMs} ms · 说话人：${m.speakerCount}');
    out.writeln('- 来源：${m.source.value} · 状态：${m.status.value}');
    out.writeln();
    if ((m.minutesMd ?? '').trim().isNotEmpty) {
      out.writeln('### AI 纪要');
      out.writeln();
      out.writeln(m.minutesMd!.trimRight());
      out.writeln();
    }
    if (m.segments.isNotEmpty) {
      out.writeln('### 逐字稿（${m.segments.length} 段）');
      out.writeln();
      for (final TranscriptSegment s in m.segments) {
        final String name = (s.speakerName == null || s.speakerName!.isEmpty)
            ? s.speakerId
            : s.speakerName!;
        out.writeln('- **[$name · ${s.startTime}ms]** ${s.text}');
      }
      out.writeln();
    }
  }
  return out.toString();
}

/// 导出数据备份 ZIP，返回**给用户展示的保存位置**。
///
/// [audioPathResolver]：给定会议返回本地音频文件路径（null/文件不存在则跳过
/// 该会议的音频）；由调用方注入（`BackendApi.getAudioPath` 已区分录音/导入
/// 两种 key 约定）。
Future<String> exportBackup({
  required List<Meeting> meetings,
  required ExportDestination destination,
  int? schemaVersion,
  DateTime? exportedAt,
  required Future<String?> Function(Meeting meeting) audioPathResolver,
}) async {
  final DateTime now = exportedAt ?? DateTime.now();
  final String stamp = _stamp(now);
  final String zipName = 'feathernote-backup-$stamp';

  // 1. 临时工作目录：backup.json + summary.md 先落盘（zip 流式读取）。
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory workDir =
      Directory(p.join(base.path, 'exports', 'backup-$stamp'));
  if (!workDir.existsSync()) {
    await workDir.create(recursive: true);
  }
  final File jsonFile = File(p.join(workDir.path, 'backup.json'));
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(buildBackupJson(
      meetings: meetings,
      schemaVersion: schemaVersion,
      exportedAt: now,
    )),
    flush: true,
  );
  final File mdFile = File(p.join(workDir.path, 'summary.md'));
  await mdFile.writeAsString(
    buildBackupMarkdown(meetings: meetings, exportedAt: now),
    flush: true,
  );

  // 2. 流式打 zip：音频不整包驻留内存。
  final String zipPath = p.join(base.path, 'exports', '$zipName.zip');
  final ZipFileEncoder encoder = ZipFileEncoder();
  encoder.create(zipPath);
  try {
    await encoder.addFile(jsonFile, 'backup.json');
    await encoder.addFile(mdFile, 'summary.md');
    for (final Meeting m in meetings) {
      final String? audioPath = await audioPathResolver(m);
      if (audioPath == null || audioPath.isEmpty) continue;
      final File audioFile = File(audioPath);
      if (!audioFile.existsSync()) continue;
      final String audioName = 'audio/${m.id}${p.extension(audioPath)}';
      await encoder.addFile(audioFile, audioName);
    }
  } finally {
    await encoder.close();
  }

  // 3. 落位：与纪要导出同通道（MediaStore 公共 Download / SAF / iOS 分享）。
  if (destination == ExportDestination.askEachTime && Platform.isAndroid) {
    final Uint8List bytes = await File(zipPath).readAsBytes();
    final String? pickedPath = await FilePicker.platform.saveFile(
      fileName: '$zipName.zip',
      bytes: bytes,
    );
    if (pickedPath == null) {
      throw const ExportCancelledException();
    }
    return pickedPath;
  }
  if (Platform.isAndroid) {
    final SaveInfo? info = await MediaStore().saveFile(
      tempFilePath: zipPath,
      dirType: DirType.download,
      dirName: DirName.download,
    );
    if (info == null) return zipPath;
    return 'Download/SmartMinutes/$zipName.zip';
  }
  return zipPath;
}

String _stamp(DateTime now) =>
    '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');
