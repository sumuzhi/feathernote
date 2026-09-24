/// AI 结构化纪要卡（HTML `.sum-card`，屏 03 与屏 11）。
///
/// 屏 11 的差异全靠数据驱动：
/// - [MinutesView.longTag] → 额外「内容较长」标签；
/// - [MinutesView.expandNote] → 摘要末尾的「展开全文 · 摘要约 1,240 字 ⌄」；
/// - [MinutesSectionView.moreLabel] → 分节底部的「查看全部 N 条 ›」。
/// 「查看完整转写」始终是卡片底部**独立的一行**（HTML `.sum-card .foot`）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_badge.dart';

/// 纪要分节。
class MinutesSectionView {
  /// 构造分节。
  const MinutesSectionView({
    required this.title,
    required this.items,
    this.orangeDots = true,
    this.moreLabel,
  });

  /// 分节标题（可含「· 共 N 条」）。
  final String title;

  /// 条目。
  final List<String> items;

  /// 圆点是否为橙色（重要决策 = 橙，讨论要点 = 灰）。
  final bool orangeDots;

  /// 「查看全部 N 条决策」文案（为空则不展示）。
  final String? moreLabel;
}

/// 纪要视图数据。
class MinutesView {
  /// 构造纪要数据。
  const MinutesView({
    required this.title,
    required this.modelTag,
    required this.abstractText,
    required this.sections,
    required this.transcriptChars,
    this.longTag = false,
    this.expandNote,
    this.onExpandAbstract,
    this.onOpenTranscript,
    this.onMore,
    this.onRetry,
  });

  /// 卡片标题（「✦ AI 结构化纪要」）。
  final String title;

  /// 模型标签（qwen3.7-plus）。
  final String modelTag;

  /// 摘要正文。
  final String abstractText;

  /// 分节列表。
  final List<MinutesSectionView> sections;

  /// 底部「查看完整转写」右侧字数（如「1,860 字 ›」）。
  final String transcriptChars;

  /// 是否展示「内容较长」标签（屏 11）。
  final bool longTag;

  /// 「展开全文 · 摘要约 N 字」文案（屏 11）。
  final String? expandNote;

  /// 点击「展开全文」。
  final VoidCallback? onExpandAbstract;

  /// 点击「查看完整转写」。
  final VoidCallback? onOpenTranscript;

  /// 点击某分节的「查看全部 N 条」（回传分节下标）。
  final ValueChanged<int>? onMore;

  /// 点击「重新生成纪要」（仅生成失败 / 空逐字稿等场景提供）。
  final VoidCallback? onRetry;
}

/// AI 结构化纪要卡。
class MinutesCard extends StatelessWidget {
  /// 构造纪要卡。
  const MinutesCard({super.key, required this.view});

  /// 纪要数据。
  final MinutesView view;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 9,
            runSpacing: 6,
            children: <Widget>[
              Text(view.title, style: AppTextStyles.cardHead),
              AppTag(text: view.modelTag),
              if (view.longTag) const AppTag(text: '内容较长', wash: true),
            ],
          ),
          const SizedBox(height: 13),
          Text(view.abstractText, style: AppTextStyles.abstract),
          if (view.onRetry != null)
            GestureDetector(
              onTap: view.onRetry,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.refresh_rounded, size: 14, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Text('重新生成纪要', style: AppTextStyles.action),
                  ],
                ),
              ),
            ),
          if (view.expandNote != null)
            GestureDetector(
              onTap: view.onExpandAbstract,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(view.expandNote!, style: AppTextStyles.action),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 13, color: AppColors.orange),
                  ],
                ),
              ),
            ),
          for (int i = 0; i < view.sections.length; i++) ...<Widget>[
            _divider(),
            Text(view.sections[i].title, style: AppTextStyles.subHead),
            const SizedBox(height: 4),
            for (final String item in view.sections[i].items)
              _BulletItem(text: item, orange: view.sections[i].orangeDots),
            if (view.sections[i].moreLabel != null)
              GestureDetector(
                onTap: view.onMore == null ? null : () => view.onMore!(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(view.sections[i].moreLabel!, style: AppTextStyles.action),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 13, color: AppColors.orange),
                    ],
                  ),
                ),
              ),
          ],
          _divider(),
          GestureDetector(
            onTap: view.onOpenTranscript,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('查看完整转写', style: AppTextStyles.subHead),
                  Text(view.transcriptChars, style: AppTextStyles.action.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.muted,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(height: 1, thickness: 1, color: AppColors.line),
      );
}

class _BulletItem extends StatelessWidget {
  const _BulletItem({required this.text, required this.orange});

  final String text;
  final bool orange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 7, 0, 7),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: -16,
            top: 8,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: orange ? AppColors.orange : AppColors.dotGray,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Text(text, style: AppTextStyles.body.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}
