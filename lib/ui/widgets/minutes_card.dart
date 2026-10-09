/// AI 结构化纪要卡（HTML `.sum-card`，屏 03 与屏 11）。
///
/// 屏 11 的差异全靠数据驱动：
/// - [MinutesView.longTag] → 额外「内容较长」标签；
/// - [MinutesView.expandNote] → 摘要末尾的「展开全文 · 摘要约 1,240 字 ⌄」；
/// - [MinutesSectionView.moreLabel] → 分节底部的「查看全部 N 条 ›」。
/// 「查看完整转写」入口已上移至顶部信息卡（[MeetingInfoCard]，按用户参考图），
/// 卡片底部不再保留独立入口行。
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
    this.expandNote,
    this.onExpandAbstract,
    this.onOpenTranscript,
    this.onMore,
    this.onRetry,
  });

  /// 卡片标题（「✦ AI 纪要」）。
  final String title;

  /// 模型标签（qwen3.7-plus）。
  final String modelTag;

  /// 摘要正文。
  final String abstractText;

  /// 分节列表。
  final List<MinutesSectionView> sections;

  /// 底部「查看完整转写」右侧字数（如「1,860 字 ›」）。
  ///
  /// 展示位置在顶部信息卡（[MeetingInfoCard]），本卡不渲染。
  final String transcriptChars;

  /// 「展开全文 · 摘要约 N 字」文案（屏 11）。
  final String? expandNote;

  /// 点击「展开全文」。
  final VoidCallback? onExpandAbstract;

  /// 点击「查看完整转写」（由顶部信息卡消费）。
  final VoidCallback? onOpenTranscript;

  /// 点击某分节的「查看全部 N 条」（回传分节下标）。
  final ValueChanged<int>? onMore;

  /// 点击「重新生成纪要」（仅生成失败 / 空逐字稿等场景提供）。
  final VoidCallback? onRetry;
}

/// AI 结构化纪要卡。
class MinutesCard extends StatelessWidget {
  /// 构造纪要卡。
  ///
  /// [margin] 默认带 16 顶部间距；用于「固定 header + 内容滚动」布局时
  /// 可传顶部为 0（由页面在滚动区外提供固定间隔，滚动时间距不消失）。
  const MinutesCard({super.key, required this.view, this.margin});

  /// 纪要数据。
  final MinutesView view;

  /// 外边距。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          margin ?? const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
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
            // 用户要求：仅保留 LLM（模型）标签，移除「内容较长」标签。
            children: <Widget>[
              Text(view.title, style: AppTextStyles.cardHead),
              AppTag(text: view.modelTag),
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
            // 分节之间不再画分割线（用户反馈横线过多影响观感），靠留白分隔。
            if (i == 0) const SizedBox(height: 14) else const SizedBox(height: 16),
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
        ],
      ),
    );
  }
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
