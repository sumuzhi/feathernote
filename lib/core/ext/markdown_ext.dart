/// Markdown 摘要抽取（core 层，供存储投影与 UI 复用）。
library;

/// 从纪要 Markdown 中抽取**一行**预览文案（用于历史卡片、导出文件名等）。
///
/// 规则：跳过空行 / 标题行（`#`）/ 列表标记 / 引用块，取第一段有效正文，
/// 去掉行内标记后按 [maxChars] 截断（超出补 `…`）。
String minutesExcerpt(String? markdown, {int maxChars = 80}) {
  if (markdown == null) return '';
  final String value = _stripInline(markdown);
  for (final String raw in value.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    if (line.startsWith('>')) continue;
    if (line.startsWith('---') || line.startsWith('***')) continue;
    final String cleaned = line
        .replaceFirst(RegExp(r'^(?:[-*+]|\d{1,2}\s*[.、)])\s*'), '')
        .trim();
    if (cleaned.isEmpty) continue;
    if (cleaned.length <= maxChars) return cleaned;
    return '${cleaned.substring(0, maxChars)}…';
  }
  return '';
}

String _stripInline(String input) {
  String out = input;
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (Match m) => m.group(1) ?? '');
  out = out.replaceAllMapped(RegExp(r'`([^`]*)`'), (Match m) => m.group(1) ?? '');
  return out;
}
