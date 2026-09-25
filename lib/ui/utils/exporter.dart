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
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

/// 按格式导出纪要（Markdown 源），返回写入后的**绝对路径**。
Future<String> exportMeeting({
  required String fileName,
  required String markdown,
  required ExportFormat format,
}) async {
  switch (format) {
    case ExportFormat.markdown:
      return exportTextFile(fileName: fileName, content: markdown, extension: '.md');
    case ExportFormat.txt:
      return exportTextFile(
        fileName: fileName,
        content: markdownToPlainText(markdown),
        extension: '.txt',
      );
    case ExportFormat.word:
      return exportBytesFile(
        fileName: fileName,
        bytes: buildDocxBytes(markdown),
        extension: '.docx',
      );
    case ExportFormat.pdf:
      return exportBytesFile(
        fileName: fileName,
        bytes: await buildPdfBytes(markdown),
        extension: '.pdf',
      );
  }
}

/// 导出文本文件，返回写入后的**绝对路径**。
///
/// [fileName] 会被安全化（去掉路径分隔符与非法字符）。
Future<String> exportTextFile({
  required String fileName,
  required String content,
  String extension = '.md',
}) =>
    exportBytesFile(
      fileName: fileName,
      bytes: utf8.encode(content),
      extension: extension,
    );

/// 导出二进制文件（docx / pdf 等共用落盘逻辑）。
Future<String> exportBytesFile({
  required String fileName,
  required List<int> bytes,
  required String extension,
}) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory dir = Directory(p.join(base.path, 'exports'));
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final String safeName = sanitizeFileName(fileName);
  final File file = File(p.join(dir.path, '$safeName$extension'));
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
