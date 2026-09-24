/// 本地导出（Markdown / 纯文本）。
///
/// 本版本不引 `share_plus`（保持零额外依赖），导出语义 = 写入应用文档目录下的
/// `exports/` 子目录，并把路径回传给 UI 提示用户。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 导出文本文件，返回写入后的**绝对路径**。
///
/// [fileName] 会被安全化（去掉路径分隔符与非法字符）。
Future<String> exportTextFile({
  required String fileName,
  required String content,
  String extension = '.md',
}) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory dir = Directory(p.join(base.path, 'exports'));
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final String safeName = sanitizeFileName(fileName);
  final File file = File(p.join(dir.path, '$safeName$extension'));
  await file.writeAsString(content, flush: true);
  return file.path;
}

/// 把任意标题安全化为文件名（保留中文，替换路径分隔符与控制字符）。
String sanitizeFileName(String input) {
  final String trimmed = input.trim();
  final String replaced = trimmed
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  final String result = replaced.isEmpty ? 'minutes' : replaced;
  return result.length > 60 ? result.substring(0, 60) : result;
}
