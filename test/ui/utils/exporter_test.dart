/// 导出模块单元测试：docx / pdf 字节合法性 + Markdown 解析。
library;

import 'package:archive/archive.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/utils/exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String sample = '''
# Q3 产品规划评审

## 重要决策

- **激活率**目标上调至 35%。
- 渠道合作 8 月底前完成落地。

## 讨论要点

`数据口径`由数据团队统一维护。

---
以上为纪要正文。
''';

  group('parseMarkdownBlocks', () {
    test('解析标题 / 列表 / 段落并剥掉行内标记', () {
      final List<ExportBlock> blocks = parseMarkdownBlocks(sample);
      expect(blocks.first.kind, 'title');
      expect(blocks.first.text, 'Q3 产品规划评审');
      expect(blocks.where((ExportBlock b) => b.kind == 'heading').length, 2);
      final List<ExportBlock> bullets =
          blocks.where((ExportBlock b) => b.kind == 'bullet').toList();
      expect(bullets.length, 2);
      expect(bullets.first.text, '激活率目标上调至 35%。');
      final List<ExportBlock> paragraphs =
          blocks.where((ExportBlock b) => b.kind == 'paragraph').toList();
      expect(paragraphs.last.text, '以上为纪要正文。');
      // 分隔线被剔除。
      expect(blocks.any((ExportBlock b) => b.text == '---'), isFalse);
    });
  });

  group('markdownToPlainText', () {
    test('输出无 Markdown 标记的纯文本', () {
      final String plain = markdownToPlainText(sample);
      expect(plain.contains('#'), isFalse);
      expect(plain.contains('**'), isFalse);
      expect(plain.contains('`'), isFalse);
      expect(plain.contains('Q3 产品规划评审'), isTrue);
    });
  });

  group('buildDocxBytes', () {
    test('是合法 zip（PK 头），解压后 document.xml 含正文', () {
      final List<int> bytes = buildDocxBytes(sample);
      expect(bytes.length, greaterThan(200));
      // zip 本地文件头魔数。
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      // zip 内容是压缩的，需解包后再校验文本。
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final ArchiveFile? document = archive.findFile('word/document.xml');
      expect(document, isNotNull);
      final String xml = utf8.decode(document!.content as List<int>);
      expect(xml.contains('激活率'), isTrue);
      expect(xml.contains('重要决策'), isTrue);
      expect(xml.contains('&lt;'), isFalse); // 无意外转义
    });
  });

  group('buildPdfBytes', () {
    test('生成 %PDF 头且包含中文字体内嵌', () async {
      final List<int> bytes = await buildPdfBytes(sample);
      final String header = String.fromCharCodes(bytes.take(8));
      expect(header, startsWith('%PDF'));
      // 字体被内嵌为 FontFile 流。
      final String asLatin = String.fromCharCodes(bytes);
      expect(asLatin.contains('FontFile'), isTrue);
    });
  });

  group('sanitizeFileName', () {
    test('替换路径分隔符与非法字符并截断', () {
      expect(sanitizeFileName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(sanitizeFileName('   '), 'minutes');
      expect(sanitizeFileName('长' * 80).length, 60);
    });
  });
}
