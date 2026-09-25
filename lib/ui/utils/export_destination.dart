/// 导出位置设置：默认公共 Download/SmartMinutes/，可选「每次导出时选择」。
///
/// 选择结果持久化在应用文档目录 `exports/.destination`（纯文本，值见
/// [ExportDestination.name]），避免为此引入 shared_preferences。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 导出位置模式。
enum ExportDestination {
  /// 默认：公共下载目录 `Download/SmartMinutes/`（MediaStore 写入，
  /// Android 10+ 无需任何权限）。
  appDownload,

  /// 每次导出时弹系统「另存为」由用户选位置与文件名（SAF）。
  askEachTime,
}

/// 当前生效的导出位置（读持久化值；读不到回落 [ExportDestination.appDownload]）。
Future<ExportDestination> loadExportDestination() async {
  try {
    final Directory base = await getApplicationDocumentsDirectory();
    final File file = File(p.join(base.path, 'exports', '.destination'));
    if (!file.existsSync()) return ExportDestination.appDownload;
    final String value = file.readAsStringSync().trim();
    return ExportDestination.values
            .where((ExportDestination d) => d.name == value)
            .firstOrNull ??
        ExportDestination.appDownload;
  } catch (_) {
    return ExportDestination.appDownload;
  }
}

/// 持久化导出位置选择。
Future<void> saveExportDestination(ExportDestination destination) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory dir = Directory(p.join(base.path, 'exports'));
  if (!dir.existsSync()) await dir.create(recursive: true);
  await File(p.join(dir.path, '.destination'))
      .writeAsString(destination.name, flush: true);
}

/// 设置页 / 弹层里展示的位置文案。
String exportDestinationLabel(ExportDestination destination) =>
    switch (destination) {
      ExportDestination.appDownload => 'Download/SmartMinutes',
      ExportDestination.askEachTime => '每次导出时选择',
    };
