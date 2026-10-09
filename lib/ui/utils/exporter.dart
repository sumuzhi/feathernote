/// 本地导出（Markdown / TXT / Word / PDF）。
///
/// 导出语义 = 写入应用文档目录下的 `exports/` 子目录，并把路径回传给 UI 提示。
/// - Markdown / TXT：纯文本（UTF-8）；
/// - Word（.docx）：纯 Dart 生成最小 OOXML 包（zip + document.xml），Word/WPS 可直接打开，
///   中文字体由查看端系统渲染，无嵌入需求；
/// - PDF：`pdf` 包生成，嵌入随包的 NotoSansSC 字体（中文不缺字形）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'export_destination.dart';

/// 公共下载子目录的位置标签（导出成功时给用户展示的「位置」）。
const String kExportLocationDownload = 'Download/SmartMinutes';

/// 回落位置标签：文件只写进了应用文档目录（用户无法用文件管理器直接浏览）。
const String kExportLocationAppDocs = '应用文档目录';

/// 写入公共 `Download/SmartMinutes/`（MediaStore），返回**给用户展示的位置标签**。
///
/// 实测（2026-10-10，OPPO PKX110 / ColorOS Android 15）：`saveFile` 可能返回
/// null 但文件**已成功写入**公共目录（插件 native 返回的 JSON 解析失败），
/// 因此不能拿返回值当成败依据——为 null 时用 `getFileUri` 复核，确认写入了
/// 才报 `Download/SmartMinutes`，否则如实回落 [kExportLocationAppDocs]。
Future<String> saveToPublicDownload({
  required String tempFilePath,
  required String fileName,
}) async {
  final SaveInfo? info = await MediaStore().saveFile(
    tempFilePath: tempFilePath,
    dirType: DirType.download,
    dirName: DirName.download,
  );
  if (info != null) return kExportLocationDownload;
  try {
    final Uri? uri = await MediaStore().getFileUri(
      fileName: fileName,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: MediaStore.appFolder,
    );
    if (uri != null) return kExportLocationDownload;
  } catch (_) {
    // 复核通道本身不可用（未初始化等）→ 如实报应用内位置。
  }
  return kExportLocationAppDocs;
}

/// 导出格式。
enum ExportFormat {
  /// Markdown（.md）。
  markdown,

  /// PDF（.pdf）。
  pdf,

  /// Word（.docx）。
  word,

  /// 纯文本（.txt）。
  txt,
}

/// 格式的扩展名。
extension ExportFormatX on ExportFormat {
  /// 文件扩展名（含点）。
  String get extension => switch (this) {
        ExportFormat.markdown => '.md',
        ExportFormat.pdf => '.pdf',
        ExportFormat.word => '.docx',
        ExportFormat.txt => '.txt',
      };

  /// 选择器里的展示名。
  String get label => switch (this) {
        ExportFormat.markdown => 'Markdown（.md）',
        ExportFormat.pdf => 'PDF 文档（.pdf）',
        ExportFormat.word => 'Word 文档（.docx）',
        ExportFormat.txt => '纯文本（.txt）',
      };

  /// 选择器里的图标。
  String get hint => switch (this) {
        ExportFormat.markdown => '保留原始排版标记',
        ExportFormat.pdf => '定稿排版，适合存档与分享',
        ExportFormat.word => '可继续编辑，适合二次加工',
        ExportFormat.txt => '无格式纯文本，适合粘贴',
      };
}

/// 按格式导出纪要（Markdown 源），返回**给用户展示的保存位置**。
///
/// - [ExportDestination.appDownload]（默认）：Android 上经 MediaStore 写入
///   公共 `Download/SmartMinutes/`（10+ 零权限）；iOS 写应用文档目录 `exports/`
///   后**弹系统分享面板**（share_plus），面板关闭后返回本地路径；其他平台只写应用文档目录。
/// - [ExportDestination.askEachTime]：弹系统「另存为」，由用户选位置与文件名（Android）。
Future<String> exportMeeting({
  required String fileName,
  required String markdown,
  required ExportFormat format,
  ExportDestination destination = ExportDestination.appDownload,
}) async {
  final List<int> bytes = await exportBytes(markdown: markdown, format: format);
  return exportRawFile(
    fileName: fileName,
    extension: format.extension,
    bytes: bytes,
    destination: destination,
  );
}

/// 写入任意字节并按目标返回**给用户展示的保存位置**（纪要导出与数据备份共用）。
///
/// - [ExportDestination.appDownload]（默认）：Android 经 MediaStore 写公共
///   `Download/SmartMinutes/`；iOS 写应用文档目录后弹分享面板。
/// - [ExportDestination.askEachTime]：弹系统「另存为」，由用户选位置与文件名（Android）。
Future<String> exportRawFile({
  required String fileName,
  required String extension,
  required List<int> bytes,
  ExportDestination destination = ExportDestination.appDownload,
}) async {
  final String safeName = sanitizeFileName(fileName);

  // 「每次导出时选择」：系统另存为（SAF），取消返回 null。
  if (destination == ExportDestination.askEachTime && Platform.isAndroid) {
    final String? pickedPath = await FilePicker.platform.saveFile(
      fileName: '$safeName$extension',
      bytes: Uint8List.fromList(bytes),
    );
    if (pickedPath == null) {
      throw const ExportCancelledException();
    }
    // 用户刚在系统弹窗里亲自选的位置，toast 只需短文件名，不回显长路径。
    return p.basename(pickedPath);
  }

  // 默认：Android → 公共 Download/SmartMinutes/；其他平台 → 应用文档目录。
  if (Platform.isAndroid) {
    final String localPath = await _writeLocalBytes(
      bytes: bytes,
      fileName: safeName,
      extension: extension,
    );
    return saveToPublicDownload(
      tempFilePath: localPath,
      fileName: '$safeName$extension',
    );
  }

  // iOS：无「公共下载目录」概念，按产品决策走**系统分享面板**（UIActivityViewController,
  // AirDrop / 文件 / 第三方 App 均可接收）。文件先落应用文档目录 exports/，
  // 面板关闭（无论是否真的分享）后返回本地路径，调用方照常提示位置。
  final String localPath = await _writeLocalBytes(
    bytes: bytes,
    fileName: safeName,
    extension: extension,
  );
  if (Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(localPath)]),
    );
  }
  // 面板关闭后文件已交由用户处理，位置标签只说明「在应用文档目录留了底」。
  return kExportLocationAppDocs;
}

/// 用户在系统「另存为」里取消导出。
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => '已取消导出';
}

/// 生成导出字节（格式 → 字节，写盘前的一步，便于「另存为」直接带 bytes）。
Future<List<int>> exportBytes({
  required String markdown,
  required ExportFormat format,
}) async {
  switch (format) {
    case ExportFormat.markdown:
      return utf8.encode(markdown);
    case ExportFormat.txt:
      return utf8.encode(markdownToPlainText(markdown));
    case ExportFormat.word:
      return buildDocxBytes(markdown);
    case ExportFormat.pdf:
      return buildPdfBytes(markdown);
  }
}

/// 写入应用文档目录 `exports/`，返回本地绝对路径（临时中转 / 非安卓默认位置）。
Future<String> _writeLocalBytes({
  required List<int> bytes,
  required String fileName,
  required String extension,
}) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory dir = Directory(p.join(base.path, 'exports'));
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final File file = File(p.join(dir.path, '$fileName$extension'));
  await file.writeAsBytes(bytes, flush: true);
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

// ---------------------------------------------------------------------------
// Markdown 解析（导出共用的轻量结构化：标题 / 列表 / 段落）
// ---------------------------------------------------------------------------

/// 结构化块。
class ExportBlock {
  const ExportBlock._(this.kind, this.text, this.level);

  /// 文档标题（h1）。
  factory ExportBlock.title(String text) => ExportBlock._('title', text, 1);

  /// 小节标题（h2 及以下，level = 井号数）。
  factory ExportBlock.heading(String text, int level) =>
      ExportBlock._('heading', text, level);

  /// 列表项。
  factory ExportBlock.bullet(String text) => ExportBlock._('bullet', text, 0);

  /// 段落。
  factory ExportBlock.paragraph(String text) =>
      ExportBlock._('paragraph', text, 0);

  /// title / heading / bullet / paragraph。
  final String kind;

  /// 纯文本（已剥掉行内标记）。
  final String text;

  /// 标题级别（井号数；非标题为 0）。
  final int level;
}

/// 把 Markdown 文本解析为结构化块（导出专用，不追求完整语法覆盖）。
List<ExportBlock> parseMarkdownBlocks(String markdown) {
  final List<ExportBlock> blocks = <ExportBlock>[];
  for (final String rawLine in markdown.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty || line == '---' || line == '***') continue;
    final RegExpMatch? heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final int level = heading.group(1)!.length;
      final String text = _stripInline(heading.group(2)!);
      if (text.isEmpty) continue;
      blocks.add(level <= 1 ? ExportBlock.title(text) : ExportBlock.heading(text, level));
      continue;
    }
    final RegExpMatch? bullet =
        RegExp(r'^[-*•]\s+(.*)$').firstMatch(line) ??
            RegExp(r'^\d+[.、)]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final String text = _stripInline(bullet.group(1)!);
      if (text.isNotEmpty) blocks.add(ExportBlock.bullet(text));
      continue;
    }
    final String text = _stripInline(line);
    if (text.isNotEmpty) blocks.add(ExportBlock.paragraph(text));
  }
  return blocks;
}

/// 剥掉行内标记（加粗 / 斜体 / 行内代码 / 删除线）。
///
/// ⚠️ 必须用 `replaceAllMapped`：`replaceAll(pattern, '$1')` 是**字面量**替换，
/// 不做捕获组展开（会把 `**激活率**` 替换成字面 `$1`）。
String _stripInline(String input) {
  String group1(Match m) => m.group(1)!;
  return input
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), group1)
      .replaceAllMapped(RegExp(r'__(.+?)__'), group1)
      .replaceAllMapped(
        RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'),
        group1,
      )
      .replaceAllMapped(RegExp(r'`([^`]*)`'), group1)
      .replaceAllMapped(RegExp(r'~~(.+?)~~'), group1)
      .trim();
}

/// Markdown → 纯文本（TXT 用）：去标题 / 列表 / 强调标记，保留行文。
String markdownToPlainText(String markdown) {
  final StringBuffer out = StringBuffer();
  for (final ExportBlock block in parseMarkdownBlocks(markdown)) {
    out.writeln(block.text);
  }
  return out.toString().trimRight();
}

// ---------------------------------------------------------------------------
// Word（.docx）：最小 OOXML 包
// ---------------------------------------------------------------------------

/// 生成 .docx 字节（最小 OOXML：正文段落 + 标题加粗，WPS / Word 均可打开）。
List<int> buildDocxBytes(String markdown) {
  final Archive archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _docxContentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _docxRels))
    ..addFile(ArchiveFile.string('word/document.xml', _buildDocxDocument(markdown)));
  return ZipEncoder().encode(archive)!;
}

const String _docxContentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const String _docxRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

String _docxParagraph(String text, {required bool bold, required int halfPoints, required int beforeTwips}) {
  final String rPr = bold
      ? '<w:rPr><w:b/><w:sz w:val="$halfPoints"/></w:rPr>'
      : '<w:rPr><w:sz w:val="$halfPoints"/></w:rPr>';
  return '<w:p><w:pPr><w:spacing w:before="$beforeTwips" w:after="80"/></w:pPr>'
      '<w:r>$rPr<w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
}

String _buildDocxDocument(String markdown) {
  final StringBuffer body = StringBuffer();
  for (final ExportBlock block in parseMarkdownBlocks(markdown)) {
    switch (block.kind) {
      case 'title':
        body.write(_docxParagraph(block.text, bold: true, halfPoints: 32, beforeTwips: 0));
      case 'heading':
        body.write(_docxParagraph(block.text, bold: true, halfPoints: 26, beforeTwips: 200));
      case 'bullet':
        body.write(
          _docxParagraph('• ${block.text}', bold: false, halfPoints: 21, beforeTwips: 40),
        );
      default:
        body.write(_docxParagraph(block.text, bold: false, halfPoints: 21, beforeTwips: 40));
    }
  }
  if (body.isEmpty) body.write(_docxParagraph('（空内容）', bold: false, halfPoints: 21, beforeTwips: 0));
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body</w:body></w:document>';
}

String _escapeXml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// ---------------------------------------------------------------------------
// PDF：pdf 包 + 随包 NotoSansSC 字体
// ---------------------------------------------------------------------------

/// 生成 .pdf 字节（A4，标题/列表分层排版，中文字体内嵌）。
Future<List<int>> buildPdfBytes(String markdown) async {
  final pw.Font font =
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
  final pw.Document doc = pw.Document();
  final List<ExportBlock> blocks = parseMarkdownBlocks(markdown);

  final List<pw.Widget> children = <pw.Widget>[];
  for (final ExportBlock block in blocks) {
    switch (block.kind) {
      case 'title':
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(font: font, fontSize: 20, color: PdfColors.black),
          ),
        ));
      case 'heading':
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(font: font, fontSize: 13.5, color: PdfColors.grey900),
          ),
        ));
      case 'bullet':
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 3.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 5.5, right: 6),
                width: 3,
                height: 3,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey600,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  block.text,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 10.5,
                    height: 1.55,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
            ],
          ),
        ));
      default:
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            block.text,
            style: pw.TextStyle(
              font: font,
              fontSize: 10.5,
              height: 1.55,
              color: PdfColors.grey800,
            ),
          ),
        ));
    }
  }
  if (children.isEmpty) {
    children.add(pw.Text('（空内容）', style: pw.TextStyle(font: font, fontSize: 10.5)));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(48, 56, 48, 56),
    build: (pw.Context _) => children,
  ));
  return doc.save();
}
