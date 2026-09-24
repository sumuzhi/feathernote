/// 屏 01：待机态 · 首页（HTML `#s01`）。
library;

import 'package:flutter/material.dart';

import '../demo/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/history_card.dart';
import '../widgets/record_hero_card.dart';
import '../widgets/section_header.dart';
import '../widgets/surface_card.dart';
import 'screen_frame.dart';

/// 首页待机态。
class HomeIdleScreen extends StatelessWidget {
  /// 构造待机页。
  const HomeIdleScreen({
    super.key,
    required this.greeting,
    required this.userName,
    required this.heroStatusText,
    required this.heroStatusTail,
    required this.modes,
    required this.selectedMode,
    required this.recentItems,
    required this.onMicTap,
    required this.onModeChanged,
    required this.onViewAll,
    required this.onTabTap,
    this.selectedTab = 0,
    this.onAvatarTap,
  });

  /// 问候语（「早上好，苏木」）。
  final String greeting;

  /// 用户名（头像文字取首字）。
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
  final ValueChanged<int> onModeChanged;

  /// 点击「查看全部 ›」。
  final VoidCallback onViewAll;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 选中 Tab（默认 0 = 录音）。
  final int selectedTab;

  /// 点击右上头像。
  final VoidCallback? onAvatarTap;

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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(greeting, style: AppTextStyles.greeting),
                    const SizedBox(height: 4),
                    Text('开始记录', style: AppTextStyles.pageTitle),
                  ],
                ),
                GestureDetector(
                  onTap: onAvatarTap,
                  behavior: HitTestBehavior.opaque,
                  child: AppAvatar(text: userName.isEmpty ? '苏' : userName.characters.first),
                ),
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
