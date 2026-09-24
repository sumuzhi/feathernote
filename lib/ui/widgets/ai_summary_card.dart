/// AI 结构化纪要卡（设计稿 11 号屏 / 2:954）。
///
/// **对应用户痛点「纪要超长」**，这里刻意做成「折叠 → 分节 → 独立入口」三层：
/// 1. 摘要**默认折叠**，一行 `展开全文 · 摘要约 N 字` 控制；
/// 2. 结构化分节（重要决策 / 讨论要点…）各自 `查看全部 N 条`，就地展开，不发生长滚动；
/// 3. `查看完整转写` 是**独立入口行**（右侧带字数），跳转到完整转写页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/app_theme.dart';
import '../theme/markdown_style.dart';
import '../utils/formatters.dart';
import '../utils/minutes_outline.dart';
import 'app_badge.dart';
import 'surface_card.dart';

/// AI 结构化纪要卡。
class AISummaryCard extends StatefulWidget {
  /// 构造纪要卡。
  const AISummaryCard({
    super.key,
    required this.markdown,
    required this.transcriptChars,
    required this.onOpenTranscript,
    this.modelName,
    this.generating = false,
    this.error,
    this.onRetry,
    this.maxSections = 2,
    this.sectionPreviewItems = 2,
  });

  /// 纪要 Markdown（生成中时为已收到的增量）。
  final String markdown;

  /// 完整转写字数（「查看完整转写 / 1,860 字」）。
  final int transcriptChars;

  /// 打开完整转写。
  final VoidCallback onOpenTranscript;

  /// 模型名（展示为 chip）。
  final String? modelName;

  /// 是否正在生成（打字机态）。
  final bool generating;

  /// 生成错误提示（非空时展示错误态）。
  final String? error;

  /// 重试回调。
  final VoidCallback? onRetry;

  /// 最多展示几个结构化分节。
  final int maxSections;

  /// 每个分节默认预览几条。
  final int sectionPreviewItems;

  @override
  State<AISummaryCard> createState() => _AISummaryCardState();
}

class _AISummaryCardState extends State<AISummaryCard> {
  bool _summaryExpanded = false;
  final Set<String> _expandedSections = <String>{};

  @override
  void didUpdateWidget(AISummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一篇纪要（如重新生成完成）→ 折叠态复位。
    if (oldWidget.markdown != widget.markdown &&
        oldWidget.markdown.length > widget.markdown.length) {
      _summaryExpanded = false;
      _expandedSections.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MinutesOutline outline = parseMinutesOutline(widget.markdown);
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.cardSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(
            modelName: widget.modelName,
            generating: widget.generating,
            longContent: outline.summaryChars > 400,
          ),
          const SizedBox(height: AppSpacing.gapSm),
          _buildBody(outline),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppColors.hairline),
          _TranscriptEntry(
            chars: widget.transcriptChars,
            onTap: widget.onOpenTranscript,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(MinutesOutline outline) {
    final String? error = widget.error;
    if (error != null) {
      return _ErrorBlock(message: error, onRetry: widget.onRetry);
    }
    if (outline.isEmpty) {
      return _PendingBlock(generating: widget.generating);
    }
    final List<MinutesSection> sections =
        outline.itemizedSections.take(widget.maxSections).toList(growable: false);
    final List<MinutesSection> prose =
        outline.proseSections.take(1).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (outline.summary.isNotEmpty) ...<Widget>[
          _SummaryBlock(
            summary: outline.summary,
            chars: outline.summaryChars,
            expanded: _summaryExpanded,
            onToggle: () => setState(() => _summaryExpanded = !_summaryExpanded),
          ),
          const SizedBox(height: AppSpacing.gapSm),
        ],
        for (final MinutesSection section in sections) ...<Widget>[
          _SectionBlock(
            section: section,
            accent: sections.indexOf(section) == 0 ? AppColors.primary : AppColors.dot,
            expanded: _expandedSections.contains(section.title),
            previewCount: widget.sectionPreviewItems,
            onToggle: () => setState(() {
              if (!_expandedSections.remove(section.title)) {
                _expandedSections.add(section.title);
              }
            }),
          ),
          const Divider(height: AppSpacing.gapLg, color: AppColors.hairline),
        ],
        for (final MinutesSection section in prose) ...<Widget>[
          _ProseBlock(section: section),
          const SizedBox(height: AppSpacing.gapSm),
        ],
        if (widget.generating)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('▍正在生成…', style: AppTextStyles.metaSmall),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.modelName,
    required this.generating,
    required this.longContent,
  });

  final String? modelName;
  final bool generating;
  final bool longContent;

  @override
  Widget build(BuildContext context) {
    final String? model = modelName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        const Text('AI 结构化纪要', style: AppTextStyles.label),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (model != null && model.isNotEmpty)
                AppBadge(label: model, tone: BadgeTone.slate),
              if (generating) const AppBadge(label: '生成中'),
              if (longContent) const AppBadge(label: '内容较长'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.summary,
    required this.chars,
    required this.expanded,
    required this.onToggle,
  });

  final String summary;
  final int chars;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (expanded)
          MarkdownBody(
            data: summary,
            selectable: true,
            styleSheet: buildMinutesMarkdownStyleSheet(),
          )
        else
          Text(
            summary,
            style: AppTextStyles.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 6),
        _ToggleLink(
          label: expanded ? '收起摘要' : '展开全文 · 摘要约 ${formatThousands(chars)} 字',
          expanded: expanded,
          onTap: onToggle,
        ),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.section,
    required this.accent,
    required this.expanded,
    required this.previewCount,
    required this.onToggle,
  });

  final MinutesSection section;
  final Color accent;
  final bool expanded;
  final int previewCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final List<String> items = expanded
        ? section.items
        : section.items.take(previewCount).toList(growable: false);
    final bool hasMore = section.total > items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                section.title,
                style: AppTextStyles.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('  ·  共 ${section.total} 条', style: AppTextStyles.metaSmall),
          ],
        ),
        const SizedBox(height: 8),
        for (final String item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item, style: AppTextStyles.body)),
              ],
            ),
          ),
        if (hasMore || expanded)
          _ToggleLink(
            label: expanded ? '收起' : '查看全部 ${section.total} 条${section.noun}',
            expanded: expanded,
            onTap: onToggle,
          ),
      ],
    );
  }
}

class _ProseBlock extends StatelessWidget {
  const _ProseBlock({required this.section});

  final MinutesSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(section.title, style: AppTextStyles.label),
        const SizedBox(height: 6),
        MarkdownBody(
          data: section.body,
          selectable: true,
          styleSheet: buildMinutesMarkdownStyleSheet(),
        ),
      ],
    );
  }
}

class _ToggleLink extends StatelessWidget {
  const _ToggleLink({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: AppTextStyles.link),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.primaryDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriptEntry extends StatelessWidget {
  const _TranscriptEntry({required this.chars, required this.onTap});

  final int chars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text('查看完整转写', style: AppTextStyles.label),
              ),
              Text(formatCharCount(chars), style: AppTextStyles.meta),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBlock extends StatelessWidget {
  const _PendingBlock({required this.generating});

  final bool generating;

  @override
  Widget build(BuildContext context) {
    if (!generating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('暂无纪要内容', style: AppTextStyles.meta),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('正在生成结构化纪要…', style: AppTextStyles.body),
        const SizedBox(height: AppSpacing.gapSm),
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.trackSoft,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardSm),
      decoration: BoxDecoration(
        color: AppColors.badgeOrangeBg,
        borderRadius: BorderRadius.circular(AppRadius.infoBar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: AppTextStyles.meta.copyWith(color: AppColors.badgeOrangeFg),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 8),
            _ToggleLink(label: '重新生成', expanded: false, onTap: onRetry!),
          ],
        ],
      ),
    );
  }
}
