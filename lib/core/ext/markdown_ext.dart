/// Markdown 摘要抽取（core 层，供存储投影与 UI 复用）。
library;

/// 摘要候选标题关键词（按优先级；单一真相源）。
///
/// 与 `ui/utils/minutes_outline.dart` 的 `parseMinutesOutline` 摘要小节
/// 判定**同源**：详情页摘要与历史卡 desc 都以此定位「核心观点 / 摘要」小节。
const List<String> kSummaryTitleKeywords = <String>[
  '200字摘要',
  '200 字摘要',
  '核心观点',
  '摘要',
  '一句话总结',
];

/// 命中摘要小节标题（标题文本包含任一关键词，如 `# 核心观点` / `## 摘要`）。
bool _isSummaryHeading(String headingTitle) {
  for (final String keyword in kSummaryTitleKeywords) {
    if (headingTitle.contains(keyword)) return true;
  }
  return false;
}

/// 单行清洗：跳过空行 / 标题 / 引用 / 分隔线，剥掉列表标记；无正文返回 null。
String? _cleanBodyLine(String raw) {
  final String line = raw.trim();
  if (line.isEmpty) return null;
  if (line.startsWith('#') || line.startsWith('>')) return null;
  if (line.startsWith('---') || line.startsWith('***')) return null;
  final String cleaned = line
      .replaceFirst(RegExp(r'^(?:[-*+]|\d{1,2}\s*[.、)])\s*'), '')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// 摘要小节（若有）内的首个正文行；无摘要小节或小节无正文返回 null。
String? _firstBodyAfterSummaryHeading(String md) {
  bool inSummary = false;
  for (final String raw in md.split('\n')) {
    final String line = raw.trim();
    final RegExpMatch? heading =
        RegExp(r'^(#{1,6})\s*(.+)$').firstMatch(line);
    if (heading != null) {
      if (inSummary) return null; // 摘要小节结束（遇到下一个标题）且无正文
      if (_isSummaryHeading(heading.group(2)!.trim())) inSummary = true;
      continue;
    }
    if (!inSummary) continue;
    final String? cleaned = _cleanBodyLine(line);
    if (cleaned != null) return cleaned;
  }
  return null;
}

/// 全文首个正文行（旧行为，回落用）。
String? _firstBodyLine(String md) {
  for (final String raw in md.split('\n')) {
    final String? cleaned = _cleanBodyLine(raw);
    if (cleaned != null) return cleaned;
  }
  return null;
}

/// 从纪要 Markdown 中抽取**一行**预览文案（用于历史卡片、导出文件名等）。
///
/// 规则（2026-10-09 根因修复）：
/// ① **优先取「摘要小节」**（`# 核心观点` / `## 摘要` 等关键词小节）的首段正文
///    —— 与详情页摘要（`parseMinutesOutline.summary`）**同源**。
///    旧实现取「全文第一段正文」，而知识沉淀型纪要的开头是「分享主题」引言，
///    导致历史卡 desc 与详情页纪要内容天然对不上；
/// ② 无摘要小节时回落全文第一段正文；
/// ③ 剥掉行内标记（链接 / 加粗 / 代码）后按 [maxChars] 截断（超出补 `…`）。
String minutesExcerpt(String? markdown, {int maxChars = 80}) {
  if (markdown == null) return '';
  final String value = _stripInline(markdown);
  final String? body = _firstBodyAfterSummaryHeading(value) ?? _firstBodyLine(value);
  if (body == null || body.isEmpty) return '';
  return body.length <= maxChars ? body : '${body.substring(0, maxChars)}…';
}

String _stripInline(String input) {
  String out = input;
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'`([^`]*)`'), (Match m) => m.group(1) ?? '');
  return out;
}
