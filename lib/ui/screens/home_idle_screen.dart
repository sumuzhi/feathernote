/// 屏 01：待机态 · 首页（HTML `#s01`）。
library;

import 'package:flutter/material.dart';

import '../demo/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/app_badge.dart';
import '../widgets/history_card.dart';
import '../widgets/record_hero_card.dart';
import '../widgets/section_header.dart';
import '../widgets/surface_card.dart';
import 'screen_frame.dart';

/// 首页待机态。
class HomeIdleScreen extends StatelessWidget {
  /// 构造待机页。
  ///
  /// [greeting] / [userName] 传入非空才渲染（App 无登录，首页默认不传 →
  /// 不显示问候语与头像；屏幕目录 demo 态仍可传值展示设计稿形态）。
  const HomeIdleScreen({
    super.key,
    this.greeting = '',
    this.dailyQuote,
    this.onQuoteTap,
    this.userName = '',
    required this.heroStatusText,
    required this.heroStatusTail,
    this.modes = const <String>[],
    this.selectedMode = 0,
    this.onModeChanged,
    required this.recentItems,
    required this.onMicTap,
    required this.onViewAll,
    required this.onTabTap,
    this.selectedTab = 0,
    this.onAvatarTap,
    this.busy = false,
    this.busyHint,
  });

  /// 问候语（「早上好，苏木」；空则不渲染）。
  final String greeting;

  /// 「一句话」文案（进入首页时从一言 API 取；null / 空 = 不渲染）。
  final String? dailyQuote;

  /// 点击「一句话」（弹详情 + 复制；null = 仅展示不可点）。
  final VoidCallback? onQuoteTap;

  /// 用户名（头像文字取首字；空则不渲染头像）。
  final String userName;

  /// Hero 状态行主文案（待机中 / 录音中）。
  final String heroStatusText;

  /// Hero 状态行尾部文案（「今日已记录 42 分钟」）。
  final String heroStatusTail;

  /// 模式列表。
  final List<String> modes;

  /// 选中模式。
  final int selectedMode;

  /// 最近记录卡片。
  final List<HistoryItemView> recentItems;

  /// 点击麦克风。
  final VoidCallback onMicTap;

  /// 切换模式。
  final ValueChanged<int>? onModeChanged;

  /// 点击「查看全部 ›」。
  final VoidCallback onViewAll;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 选中 Tab（默认 0 = 录音）。
  final int selectedTab;

  /// 点击右上头像。
  final VoidCallback? onAvatarTap;

  /// 是否「忙」（启动中 / 收尾中 / 上一段仍在生成纪要）。
  final bool busy;

  /// 忙态原因（显示在 Hero 副文案下方）。
  final String? busyHint;

/// 屏 01 的演示态（供「屏幕目录」直接使用 HTML 文案与数据）。
  factory HomeIdleScreen.demo({
    Key? key,
    required VoidCallback onMicTap,
    required ValueChanged<int> onModeChanged,
    required VoidCallback onViewAll,
    required ValueChanged<int> onTabTap,
    required void Function(int index) onRecentTap,
  }) {
    return HomeIdleScreen(
      key: key,
      greeting: '早上好，苏木',
      userName: '苏木',
      heroStatusText: '待机中',
      heroStatusTail: '今日已记录 42 分钟',
      modes: const <String>['会议', '访谈', '灵感'],
      selectedMode: 0,
      recentItems: demoRecentViews(onTap: onRecentTap),
      onMicTap: onMicTap,
      onModeChanged: onModeChanged,
      onViewAll: onViewAll,
      onTabTap: onTabTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (greeting.isNotEmpty) ...<Widget>[
                  Text(greeting, style: AppTextStyles.greeting),
                  const SizedBox(height: 4),
                ],
                Text('开始记录', style: AppTextStyles.pageTitle),
                // 「一句话」：一言 API（诗词），随每次进首页刷新；无网静默隐藏。
                // 点击弹窗查看全文并可一键复制。
                if (dailyQuote != null && dailyQuote!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onQuoteTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            dailyQuote!,
                            style: AppTextStyles.metaSmall
                                .copyWith(color: AppColors.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 14,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          RecordHeroCard(
            statusText: heroStatusText,
            statusTail: heroStatusTail,
            title: '点击开始录音',
            subtitle: '中英文自动转写 · 智能区分说话人',
            modes: modes,
            selectedMode: selectedMode,
            onModeChanged: onModeChanged,
            onMicTap: onMicTap,
            busy: busy,
            busyHint: busyHint,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 26, AppSpacing.page, 0),
            child: SectionHeader(
              title: '最近记录',
              actionLabel: '查看全部 ›',
              onAction: onViewAll,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < recentItems.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _RecentCard(item: recentItems[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页「最近记录」小卡（HTML `.rc-card`）。
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item});

  final HistoryItemView item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: item.onTap != null,
      label: item.title,
      child: GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: SurfaceCard(
          radius: AppRadius.card2,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.title,
                style: AppTextStyles.settingTitle.copyWith(fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 7),
              Text(item.description, style: AppTextStyles.metaSmall),
              const SizedBox(height: 10),
              AppBadge(
                text: item.badge == HistoryBadge.done ? '已完成' : '已总结',
                tone: item.badge == HistoryBadge.done
                    ? AppBadgeTone.done
                    : AppBadgeTone.summarized,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
