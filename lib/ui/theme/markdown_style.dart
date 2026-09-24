/// Markdown 渲染样式（`flutter_markdown_plus`），对齐 DESIGN-SPEC 的字阶与色板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/app_theme.dart';

/// 构造纪要正文的 Markdown 样式表。
MarkdownStyleSheet buildMinutesMarkdownStyleSheet() {
  const TextStyle heading = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.ink,
  );
  return MarkdownStyleSheet(
    p: AppTextStyles.body,
    pPadding: const EdgeInsets.only(bottom: 8),
    a: AppTextStyles.body.copyWith(
      color: AppColors.primaryDeep,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primaryDeep,
    ),
    em: AppTextStyles.body.copyWith(fontStyle: FontStyle.italic),
    strong: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
    del: AppTextStyles.body.copyWith(decoration: TextDecoration.lineThrough),
    h1: heading.copyWith(fontSize: 16),
    h2: heading,
    h3: heading.copyWith(fontSize: 13),
    h4: heading.copyWith(fontSize: 13),
    h5: heading.copyWith(fontSize: 12),
    h6: heading.copyWith(fontSize: 12),
    h1Padding: const EdgeInsets.only(top: 6, bottom: 6),
    h2Padding: const EdgeInsets.only(top: 6, bottom: 6),
    h3Padding: const EdgeInsets.only(top: 4, bottom: 4),
    h4Padding: const EdgeInsets.only(top: 4, bottom: 4),
    h5Padding: const EdgeInsets.only(top: 4, bottom: 4),
    h6Padding: const EdgeInsets.only(top: 4, bottom: 4),
    blockSpacing: 8,
    listIndent: 18,
    listBullet: AppTextStyles.body,
    listBulletPadding: const EdgeInsets.only(right: 6),
    code: AppTextStyles.meta.copyWith(
      fontFamily: 'monospace',
      color: AppColors.primaryDeep,
      backgroundColor: AppColors.trackSoft,
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: const BoxDecoration(
      color: AppColors.trackSoft,
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.infoBar)),
    ),
    blockquote: AppTextStyles.meta.copyWith(color: AppColors.ink2, height: 1.6),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    blockquoteDecoration: const BoxDecoration(
      color: AppColors.trackSoft,
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.infoBar)),
      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
    ),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    tableHead: AppTextStyles.label,
    tableBody: AppTextStyles.meta,
    tableBorder: TableBorder.all(color: AppColors.hairline, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tableColumnWidth: const IntrinsicColumnWidth(),
  );
}
