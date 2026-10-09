/// 屏 04 / 08 / 09 / 10：历史记录及其三个边界态（HTML `#s04` / `#s08` / `#s09` / `#s10`）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_chips.dart';
import '../widgets/history_card.dart';
import '../widgets/progress_pill.dart';
import '../widgets/search_field.dart';
import 'screen_frame.dart';

/// 历史页变体。
enum HistoryVariant {
  /// 屏 04：普通列表。
  list,

  /// 屏 08：空态（搜索与筛选禁用）。
  empty,

  /// 屏 09：超长列表（分组 + 加载更多）。
  longList,

  /// 屏 10：搜索无结果。
  searchEmpty,
}

/// 历史记录页。
class HistoryScreen extends StatelessWidget {
  /// 构造历史页。
  const HistoryScreen({
    super.key,
    required this.variant,
    required this.filters,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.onFilterButton,
    required this.onTabTap,
    required this.onStartRecording,
    this.searchController,
    this.scrollController,
    this.searchHint = '搜索会议标题、纪要或待办…',
    this.onSearchChanged,
    this.onSearchClear,
    this.items = const <HistoryItemView>[],
    this.groups = const <HistoryGroupView>[],
    this.subtitle,
    this.sortLabel = '最近优先',
    this.onSort,
    this.loadMoreText,
    this.keyword,
    this.onClearFilters,
    this.onSearchAllTime,
    this.selectedTab = 1,
  });

  /// 变体。
  final HistoryVariant variant;

  /// 过滤 chip。
  final List<FilterChipView> filters;

  /// 选中的过滤项。
  final int selectedFilter;

  /// 切换过滤项。
  final ValueChanged<int> onFilterChanged;

  /// 点击右上角筛选按钮。
  final VoidCallback onFilterButton;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 空态 CTA「开始第一次录音」。
  final VoidCallback onStartRecording;

  /// 搜索框控制器。
  final TextEditingController? searchController;

  /// 内容列表滚动控制器（页面用它恢复/缓存滚动位置）。
  final ScrollController? scrollController;

  /// 搜索占位文案。
  final String searchHint;

  /// 搜索输入回调。
  final ValueChanged<String>? onSearchChanged;

  /// 清除搜索。
  final VoidCallback? onSearchClear;

  /// 列表卡片（变体 list 使用）。
  final List<HistoryItemView> items;

  /// 分组卡片（变体 longList 使用）。
  final List<HistoryGroupView> groups;

  /// 标题下的副文案（屏 09「共 128 条 · 约 64 小时」）。
  final String? subtitle;

  /// 排序按钮文案。
  final String sortLabel;

  /// 点击排序按钮。
  final VoidCallback? onSort;

  /// 「正在加载更多」文案。
  final String? loadMoreText;

  /// 搜索关键词（屏 10 的空态文案用它）。
  final String? keyword;

  /// 屏 10「清空筛选条件」。
  final VoidCallback? onClearFilters;

  /// 屏 10「搜索全部时间」。
  final VoidCallback? onSearchAllTime;

  /// 选中 Tab（默认 1 = 历史）。
  final int selectedTab;

  bool get _isEmpty => variant == HistoryVariant.empty;
  bool get _isSearchEmpty => variant == HistoryVariant.searchEmpty;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      // 只滚动内容列表：标题 / 搜索 / 筛选 chips 固定在顶部不随列表滚动。
      scrollable: false,
      scrollController: scrollController,
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 用户要求：标题缩小（原 pageTitle 34 → sectionTitle 20）。
                      Text('历史记录', style: AppTextStyles.sectionTitle),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 5),
                        Text(subtitle!, style: AppTextStyles.meta),
                      ],
                    ],
                  ),
                ),
                // 用户要求：移除右上角筛选 icon（筛选 chips 仍保留在标题下方）。
                if (variant == HistoryVariant.longList && onSort != null)
                  _SortButton(label: sortLabel, onTap: onSort!),
              ],
            ),
          ),
          SearchField(
            hintText: _isEmpty ? '搜索会议标题或纪要内容…' : searchHint,
            controller: searchController,
            enabled: !_isEmpty,
            focused: _isSearchEmpty,
            onChanged: onSearchChanged,
            onClear: _isSearchEmpty ? onSearchClear : null,
          ),
          FilterChipRow(
            items: filters,
            onTap: onFilterChanged,
            enabled: !_isEmpty,
          ),
          // 筛选组与列表之间的呼吸间距（避免 chips 与卡片贴在一起）。
          const SizedBox(height: 10),
          Expanded(
            child: (_isEmpty || _isSearchEmpty)
                ? _buildEmptyState(context)
                : SingleChildScrollView(
                    // 底部留白 = TabBar 全保留高度 + 20 余量：
                    // 修复最后一条记录被浮动底栏遮住一半。
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      6,
                      AppSpacing.page,
                      AppTabBar.reservedHeight(context) + 20,
                    ),
                    child: _buildList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (variant == HistoryVariant.longList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final HistoryGroupView group in groups) ...<Widget>[
            AppDayLabel(label: group.day),
            for (final HistoryItemView item in group.items) ...<Widget>[
              HistoryCard(item: item),
              if (item.cut && loadMoreText != null) AppLoadMore(text: loadMoreText!),
            ],
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final HistoryItemView item in items) HistoryCard(item: item),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (_isEmpty) {
      return AppEmptyState(
        icon: Icons.mic_rounded,
        title: '还没有会议记录',
        description: '点下方按钮开始，第一段录音只需 3 秒上手',
        cta: AppEmptyCtaButton(
          label: '开始第一次录音',
          onTap: onStartRecording,
        ),
      );
    }
    return AppEmptyState(
      icon: Icons.search_off_rounded,
      title: '没有找到「${keyword ?? ''}」相关记录',
      description: '已搜索 128 条会议标题与纪要正文，换个词再试试',
      gray: true,
      titleSize: 18,
      topPadding: 96,
      actions: <Widget>[
        AppTextPillButton(
          label: '清空筛选条件',
          onTap: onClearFilters ?? () {},
        ),
        AppTextPillButton(
          label: '搜索全部时间',
          soft: true,
          onTap: onSearchAllTime ?? () {},
        ),
      ],
    );
  }
}

/// 日期分组视图。
class HistoryGroupView {
  /// 构造分组。
  const HistoryGroupView({required this.day, required this.items});

  /// 分组标题。
  final String day;

  /// 卡片。
  final List<HistoryItemView> items;
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadow.card,
          ),
          child: Row(
            children: <Widget>[
              Text(label, style: AppTextStyles.meta.copyWith(color: AppColors.ink)),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more_rounded, size: 14, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
