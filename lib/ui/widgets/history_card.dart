/// 历史记录卡片（HTML `.h-card`）：标题 + 单行省略描述 + 元信息 + 徽标。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_badge.dart';

/// 历史卡片徽标语义（与 HTML 的 `badge:'sum' | 'done'` 对应）。
enum HistoryBadge {
  /// 已总结。
  summarized,

  /// 已完成。
  done,

  /// 无徽标。
  none,
}

/// 历史卡片视图数据。
class HistoryItemView {
  /// 构造卡片数据。
  const HistoryItemView({
    required this.title,
    required this.description,
    required this.meta,
    this.badge = HistoryBadge.summarized,
    this.cut = false,
    this.dimBadge = false,
    this.onTap,
    this.onMore,
  });

  /// 标题。
  final String title;

  /// 描述（单行省略）。
  final String description;

  /// 元信息（如「32 分钟 · 今天 09:12 · 3 人」）。
  final String meta;

  /// 徽标。
  final HistoryBadge badge;

  /// 是否截断卡（s09 的 `.h-card.cut`，下方接「加载更多」）。
  final bool cut;

  /// 徽标是否半透明（s09 截断卡用 opacity .7）。
  final bool dimBadge;

  /// 点击卡片。
  final VoidCallback? onTap;

  /// 点击「···」。
  final VoidCallback? onMore;
}

/// 历史卡片。
class HistoryCard extends StatelessWidget {
  /// 构造卡片。
  const HistoryCard({super.key, required this.item});

  /// 卡片数据。
  final HistoryItemView item;

  @override
  Widget build(BuildContext context) {
    final Widget badge;
    switch (item.badge) {
      case HistoryBadge.summarized:
        badge = const AppBadge(text: '已总结', tone: AppBadgeTone.summarized);
      case HistoryBadge.done:
        badge = const AppBadge(text: '已完成', tone: AppBadgeTone.done);
      case HistoryBadge.none:
        badge = const SizedBox.shrink();
    }
    return Semantics(
      button: item.onTap != null,
      label: item.title,
      child: GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.card2),
              topRight: const Radius.circular(AppRadius.card2),
              bottomLeft: Radius.circular(item.cut ? 0 : AppRadius.card2),
              bottomRight: Radius.circular(item.cut ? 0 : AppRadius.card2),
            ),
            boxShadow: AppShadow.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      style: AppTextStyles.itemTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: item.onMore,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 44,
                      height: 28,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '···',
                          style: AppTextStyles.itemTitle.copyWith(
                            color: AppColors.faint,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.description,
                style: AppTextStyles.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 11),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.meta,
                      style: AppTextStyles.metaSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Opacity(opacity: item.dimBadge ? 0.7 : 1, child: badge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日期分组标题（HTML `.day-label`）。
class AppDayLabel extends StatelessWidget {
  /// 构造日期标题。
  const AppDayLabel({super.key, required this.label});

  /// 文案（今天 / 昨天 / 09-18）。
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
      child: Text(label, style: AppTextStyles.meta),
    );
  }
}
