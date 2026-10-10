/// `exportBackup` 完整链路回归（后台 isolate 消息循环 + 取消哨兵）。
///
/// 历史缺陷回归（2026-10-10 真机实测「导出卡在 100%」）：
/// 主线程 `await for (msg in report)` 内用 `switch` + `break` —— Dart 的
/// break 只跳出 switch、跳不出 await for；后台 isolate 发完 done/error 即
/// 退出且无人关闭 report 端口 → 主线程永久挂起。此前单测只覆盖纯函数
/// （buildLocalBackupZip 等），完整链路无测试，故带病发布。
///
/// 本文件端到端调用 [exportBackup]（macOS 测试环境走「应用文档目录」分支，
/// 无需 MediaStore 通道桩，只需伪造 path_provider）。若消息循环再次挂起，
/// 测试将超时失败。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/utils/backup_exporter.dart';
import 'package:smart_minutes_flutter/ui/utils/export_destination.dart';
import 'package:smart_minutes_flutter/ui/utils/exporter.dart'
    show ExportCancelledException, kExportLocationAppDocs;

/// 伪造 path_provider：把应用文档目录指到本测试的临时目录。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

Meeting _meeting(String id) => Meeting(
      id: id,
      title: '回归测试会议 $id',
      createdAt: DateTime(2026, 10, 10, 9),
      durationMs: 60000,
      sampleRate: 16000,
      speakerCount: 1,
      status: MeetingStatus.minutesReady,
      source: MeetingSource.microphone,
      finalizeStatus: FinalizeStatus.done,
      transcriptSource: TranscriptSource.filetrans,
      audioStatus: AudioStatus.none,
      audioBytes: 0,
      minutesPartial: false,
      minutesMd: '# 结论\n\n一切正常。',
      segments: const <TranscriptSegment>[],
      speakers: const <Speaker>[],
    );

void main() {
  late Directory base;

  setUpAll(() {
    base = Directory.systemTemp.createTempSync('backup_exporter_test');
    PathProviderPlatform.instance = _FakePathProvider(base.path);
  });

  tearDownAll(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test(
    'exportBackup 正常完成：done 消息必须退出 isolate 消息循环（卡 100% 回归）',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final List<double> progress = <double>[];
      final ({String location, BackupCancelToken handle}) result =
          await exportBackup(
        meetings: <Meeting>[_meeting('m1')],
        destination: ExportDestination.appDownload,
        schemaVersion: 1,
        audioPathResolver: (Meeting m) async => null,
        onProgress: (double fraction, String phase) => progress.add(fraction),
      );

      // 测试环境（非 Android）走「应用文档目录」分支；关键断言是函数必须**返回**。
      expect(result.location, kExportLocationAppDocs);
      // 序列化 / 纪要写入 / 落盘各阶段都应回报过进度（含最终 1.0）。
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    },
  );

  test(
    'buildLocalBackupFiles：backup.json + 每场会议一个「会议名」文件夹（含 md）',
    () async {
      final Directory workDir =
          Directory(p.join(base.path, 'files-stage'));
      final List<(String, String)> files = await buildLocalBackupFiles(
        backupMap: buildBackupJson(
          meetings: <Meeting>[_meeting('f1'), _meeting('f2')],
          schemaVersion: 1,
          exportedAt: DateTime(2026, 10, 10),
        ),
        workDirPath: workDir.path,
        onProgress: (double _, String __) {},
        isCancelled: () => false,
      );

      expect(files.length, 3);
      // 首个是 backup.json 且真实落盘。
      expect(p.basename(files[0].$1), 'backup.json');
      expect(File(files[0].$1).existsSync(), isTrue);
      // 每场会议一个「会议名」文件夹，内含同名 md。
      expect(files[1].$2, '回归测试会议 f1/回归测试会议 f1.md');
      expect(files[2].$2, '回归测试会议 f2/回归测试会议 f2.md');
      expect(File(files[1].$1).existsSync(), isTrue);
      // md 内容与会议映射一致（含标题）。
      expect(File(files[1].$1).readAsStringSync(), contains('回归测试会议 f1'));
    },
  );

  test(
    'buildLocalBackupFiles：重名会议文件夹去重（追加 -2 / -3）',
    () async {
      final Directory workDir =
          Directory(p.join(base.path, 'files-stage-dup'));
      final Meeting dup = _meeting('d1').copyWith(title: '同名会议');
      final List<(String, String)> files = await buildLocalBackupFiles(
        backupMap: buildBackupJson(
          meetings: <Meeting>[dup, dup.copyWith(id: 'd2')],
          schemaVersion: 1,
          exportedAt: DateTime(2026, 10, 10),
        ),
        workDirPath: workDir.path,
        onProgress: (double _, String __) {},
        isCancelled: () => false,
      );

      expect(files[1].$2, '同名会议/同名会议.md');
      expect(files[2].$2, '同名会议-2/同名会议-2.md');
    },
  );

  test(
    '取消导出 → 抛 ExportCancelledException（取消哨兵跨 isolate 还原回归）',
    timeout: const Timeout(Duration(seconds: 30)),
    () async {
      final BackupCancelToken token = BackupCancelToken();
      // 提前请求取消：绑定控制端口后立即送达；200 场会议提供大量检查点，
      // 确保取消在导出完成前被 isolate 处理。
      token.cancel();

      await expectLater(
        exportBackup(
          meetings: <Meeting>[
            for (int i = 0; i < 200; i++) _meeting('cancel-$i'),
          ],
          destination: ExportDestination.appDownload,
          audioPathResolver: (Meeting m) async => null,
          cancelToken: token,
        ),
        throwsA(isA<ExportCancelledException>()),
      );
    },
  );
}
