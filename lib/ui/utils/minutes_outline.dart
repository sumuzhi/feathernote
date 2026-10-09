/// 纪要 Markdown → 界面结构 的解析器（纯函数，便于单测）。
///
/// 供 `AISummaryCard` 使用：把模型产出的长 Markdown 拆成
/// 「摘要 + 若干分节（各带条目）」，使界面能实现设计稿 11 号屏的
/// **摘要默认折叠**与**分节查看全部 N 条**。
///
/// 解析对象是 `assets/prompts/minutes.md` 约定的输出骨架：
/// `# 分享主题` / `# 核心观点` / `# 内容总结`（`## 模块` / `### 关键经验`）/ `# 可执行建议` /
/// `# 金句摘录` / `# 200字摘要`。模型输出偶有偏差，故解析保持宽容：
/// 任意 `#`/`##`/`###` 标题都会被识别为分节，识别不到的散段归入 [MinutesOutline.tailBody]。
library;

import '../../core/ext/markdown_ext.dart' show kSummaryTitleKeywords;

/// 纪要分节。
class MinutesSection {
  /// 构造分节。
  const MinutesSection({
    required this.title,
    required this.level,
    required this.items,
    required this.body,
    required this.declaredTotal,
  });

  /// 规范化后的标题（去掉序号前缀，如「一、重要决策」→「重要决策」）。
  final String title;

  /// 标题层级（1 / 2 / 3 …）。
  final int level;

  /// 条目列表（已去掉 `-` / `1.` 等前缀，已清理行内标记）。
  final List<String> items;

  /// 无列表项时的正文（已清理行内标记）。
  final String body;

  /// 模型自报的总条数（正文出现「共 N 条」时取之），否则等于 [items] 长度。
  final int declaredTotal;

  /// 是否含条目。
  bool get hasItems => items.isNotEmpty;

  /// 条目总数（供「共 N 条」与「查看全部 N 条」）。
  int get total => declaredTotal > 0 ? declaredTotal : items.length;

  /// 「查看全部 N 条**决策**」里的名词。
  String get noun {
    for (final String keyword in _nounKeywords) {
      if (title.contains(keyword)) return keyword;
    }
    return title;
  }

  /// 正文 + 条目合并后的字符数。
  int get charCount => countChars('$body${items.join()}');
}

/// 纪要大纲。
class MinutesOutline {
  /// 构造大纲。
  const MinutesOutline({
    required this.raw,
    required this.summary,
    required this.sections,
    required this.tailBody,
  });

  /// 原始 Markdown。
  final String raw;

  /// 摘要正文（已清理行内标记）。
  final String summary;

  /// 全部分节（按出现顺序，已剔除被用作摘要的那一节）。
  final List<MinutesSection> sections;

  /// 未归入任何分节的散段。
  final String tailBody;

  /// 是否有可结构化展示的内容。
  bool get isEmpty => summary.isEmpty && sections.isEmpty && tailBody.isEmpty;

  /// 摘要字符数（「摘要约 N 字」）。
  int get summaryChars => countChars(summary);

  /// 有列表项的分节（优先展示，对应设计稿的「重要决策 / 讨论要点」）。
  List<MinutesSection> get itemizedSections =>
      sections.where((MinutesSection s) => s.hasItems).toList(growable: false);

  /// 无列表项但有正文的分节。
  List<MinutesSection> get proseSections =>
      sections.where((MinutesSection s) => !s.hasItems && s.body.isNotEmpty).toList(growable: false);
}

/// 摘要候选标题关键词已上移至 `core/ext/markdown_ext.dart` 的
/// [kSummaryTitleKeywords]（与历史卡 desc 提取同源，单一真相源）。

/// 名词归并表（标题 → 短名词）。
const List<String> _nounKeywords = <String>[
  '决策',
  '要点',
  '建议',
  '方法论',
  '关键经验',
  '经验',
  '案例',
  '金句',
  '注意事项',
  '结论',
  '主题',
];

/// 解析纪要 Markdown。
MinutesOutline parseMinutesOutline(String markdown) {
  final _ParseResult parsed = _parseSections(markdown);
  final String summary = parsed.summary;
  final List<MinutesSection> sections = parsed.sections
      .where((MinutesSection s) => s.title != parsed.summarySourceTitle)
      .toList(growable: false);

  return MinutesOutline(
    raw: markdown,
    summary: summary,
    sections: sections,
    tailBody: parsed.tailBody,
  );
}

/// 解析列表项，返回清理后的条目文本；非列表行返回 null。
String? parseListItem(String line) {
  final String trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final RegExpMatch? bullet = RegExp(r'^(?:[-*+]|•)\s+(.*)$').firstMatch(trimmed);
  if (bullet != null) {
    final String text = cleanInline(bullet.group(1)!);
    return text.isEmpty ? null : text;
  }
  final RegExpMatch? ordered = RegExp(r'^\d{1,2}\s*[.、)]\s*(.*)$').firstMatch(trimmed);
  if (ordered != null) {
    final String text = cleanInline(ordered.group(1)!);
    return text.isEmpty ? null : text;
  }
  return null;
}

/// 去掉标题里的序号 / 装饰前缀：`一、重要决策` → `重要决策`；`**核心**` → `核心`。
String normalizeSectionTitle(String title) {
  String out = cleanInline(title);
  out = out.replaceFirst(
    RegExp(r'^(?:第?[一二三四五六七八九十百]+|模块[一二三四五六七八九十]+)\s*[、.．:：]\s*'),
    '',
  );
  out = out.replaceFirst(RegExp(r'^\d{1,2}\s*[、.．)]\s*'), '');
  return out.trim();
}

/// 清理行内 Markdown 标记（加粗 / 斜体 / 行内代码 / 链接 / 删除线 / 标题井号）。
String cleanInline(String input) {
  String out = input;
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'__(.+?)__'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(
    RegExp(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'),
    (Match m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(RegExp(r'~~(.+?)~~'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'`([^`]*)`'), (Match m) => m.group(1) ?? '');
  out = out.replaceAll(RegExp(r'^#+\s*'), '');
  return out.trim();
}

/// 字符数：剔除空白后的长度（中文场景下与「字数」直觉一致）。
int countChars(String text) => text.replaceAll(RegExp(r'\s'), '').length;

class _ParseResult {
  const _ParseResult({
    required this.sections,
    required this.summary,
    required this.summarySourceTitle,
    required this.tailBody,
  });

  final List<MinutesSection> sections;
  final String summary;
  final String summarySourceTitle;
  final String tailBody;
}

_ParseResult _parseSections(String markdown) {
  final List<String> lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final List<MinutesSection> sections = <MinutesSection>[];
  final List<String> preamble = <String>[];

  String? title;
  int level = 1;
  final List<String> body = <String>[];
  final List<String> items = <String>[];

  void flush() {
    if (title == null) return;
    final String joined = body.join('\n').trim();
    sections.add(
      MinutesSection(
        title: normalizeSectionTitle(title!),
        level: level,
        items: List<String>.unmodifiable(items),
        body: joined,
        declaredTotal: _declaredTotalCount(joined, items.length),
      ),
    );
    title = null;
    body.clear();
    items.clear();
  }

  for (final String raw in lines) {
    final String line = raw.trimRight();
    final RegExpMatch? heading = RegExp(r'^(#{1,6})\s*(.+)$').firstMatch(line.trim());
    if (heading != null) {
      flush();
      title = heading.group(2)!.trim();
      level = heading.group(1)!.length;
      continue;
    }
    final String? item = parseListItem(line);
    if (item != null) {
      if (title == null) {
        preamble.add(item);
      } else {
        items.add(item);
      }
      continue;
    }
    if (line.trim().isEmpty) {
      if (title != null && body.isNotEmpty) body.add('');
      continue;
    }
    if (title == null) {
      preamble.add(line.trim());
    } else {
      body.add(line.trim());
    }
  }
  flush();

  final String summary = _pickSummaryText(sections, preamble);
  final String sourceTitle = _summarySourceTitle(sections, preamble, summary);

  return _ParseResult(
    sections: sections,
    summary: summary,
    summarySourceTitle: sourceTitle,
    tailBody: sections.isEmpty ? preamble.join('\n').trim() : '',
  );
}

String _pickSummaryText(List<MinutesSection> sections, List<String> preamble) {
  for (final String keyword in kSummaryTitleKeywords) {
    for (final MinutesSection section in sections) {
      if (!section.title.contains(keyword)) continue;
      final String text =
          section.body.isNotEmpty ? section.body : section.items.join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }
  }
  final String fallback = preamble.join('\n').trim();
  if (fallback.isNotEmpty) return fallback;
  for (final MinutesSection section in sections) {
    if (section.body.isNotEmpty) return section.body;
  }
  return '';
}

String _summarySourceTitle(
  List<MinutesSection> sections,
  List<String> preamble,
  String summary,
) {
  if (summary.isEmpty) return '';
  for (final String keyword in kSummaryTitleKeywords) {
    for (final MinutesSection section in sections) {
      if (!section.title.contains(keyword)) continue;
      final String text =
          section.body.isNotEmpty ? section.body : section.items.join('\n');
      if (text.trim() == summary) return section.title;
    }
  }
  return '';
}

int _declaredTotalCount(String body, int itemCount) {
  final RegExpMatch? match = RegExp(r'共\s*(\d{1,3})\s*条').firstMatch(body);
  if (match == null) return itemCount;
  final int? parsed = int.tryParse(match.group(1)!);
  if (parsed == null || parsed < itemCount) return itemCount;
  return parsed;
}
