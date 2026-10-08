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

  /// 导入（来源 = 视频 / 音频导入）。
  imported,

  /// 导入失败。
  importFailed,

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
    this.processing = false,
    this.onTap,
    this.onMore,
    this.dismissKey,
    this.confirmDismiss,
    this.onDismissed,
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

  /// 是否「导入处理中」角标（imported 会议在 pending/extracting/transcribing/minutes）。
  final bool processing;

  /// 点击卡片。
  final VoidCallback? onTap;

  /// 点击「···」。
  final VoidCallback? onMore;

  /// 左滑删除的 Dismissible key（唯一标识；为 null = 不支持滑动删除）。
  ///
  /// 必须用**稳定标识**（如会议 ID）而不是 widget 实例：列表每次重建都会
  /// 新建 [HistoryItemView]，用实例会导致 Dismissible 状态错乱。
  final Object? dismissKey;

  /// 左滑到底后确认删除（弹确认框，返回是否确认删除）。
  final Future<bool> Function()? confirmDismiss;

  /// 确认删除、卡片滑出动画结束后执行（真正删除数据）。
  final VoidCallback? onDismissed;
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
      case HistoryBadge.imported:
        badge = const AppBadge(text: '导入', tone: AppBadgeTone.neutral);
      case HistoryBadge.importFailed:
        badge = const AppBadge(text: '导入失败', tone: AppBadgeTone.neutral);
      case HistoryBadge.none:
        badge = const SizedBox.shrink();
    }
    final Widget card = Container(
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
                    // 操作 icon：More.svg 三点（#C4B3A4，18×18，点径 2.4）。
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (int i = 0; i < 3; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 2.5),
                            Container(
                              width: 2.4,
                              height: 2.4,
                              decoration: const BoxDecoration(
                                color: Color(0xFFC4B3A4),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
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
              if (item.processing) ...<Widget>[
                const AppBadge(text: '处理中', tone: AppBadgeTone.neutral),
                const SizedBox(width: 6),
              ],
              Opacity(opacity: item.dimBadge ? 0.7 : 1, child: badge),
            ],
          ),
        ],
      ),
    );

    final Widget content;
    if (item.dismissKey != null && item.confirmDismiss != null) {
      // 左滑删除：仅向左滑（endToStart），红色背景 + 删除图标；
      // confirmDismiss 里弹确认框，取消则卡片自动弹回。
      content = Dismissible(
        key: ValueKey<Object>(item.dismissKey!),
        direction: DismissDirection.endToStart,
        confirmDismiss: (DismissDirection _) async => await item.confirmDismiss!(),
        onDismissed: (DismissDirection _) => item.onDismissed?.call(),
        background: Container(
          margin: const EdgeInsets.only(top: 12),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(AppRadius.card2),
          ),
          child: Semantics(
            button: true,
            label: '删除',
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
        child: card,
      );
    } else {
      content = card;
    }

    return Semantics(
      button: item.onTap != null,
      label: item.title,
      child: GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
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
