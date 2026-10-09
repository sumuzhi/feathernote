/// 屏 03 / 11：AI 会议纪要（HTML `#s03` / `#s11`）。
///
/// 两屏共用布局；屏 11 的差异（「内容较长」标签、摘要折叠入口、分节「共 N 条 /
/// 查看全部 N 条」）全部由 [MinutesView] 数据驱动。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/meeting_info_card.dart';
import '../widgets/minutes_card.dart';
import '../widgets/progress_pill.dart';
import 'screen_frame.dart';

/// 纪要页。
class MinutesScreen extends StatelessWidget {
  /// 构造纪要页。
  const MinutesScreen({
    super.key,
    required this.generatedAt,
    required this.meetingTitle,
    required this.meetingMeta,
    required this.badgeText,
    required this.minutes,
    required this.onClose,
    required this.onShare,
    required this.onExport,
    required this.onFavorite,
    this.favorited = false,
    this.notice,
    this.noticeAction,
    this.onNoticeAction,
    this.headerCollapsed = false,
    this.onToggleHeaderCollapse,
  });

  /// 顶栏副标题（「生成于 12:47」）。
  final String generatedAt;

  /// 会议标题。
  final String meetingTitle;

  /// 会议元信息。
  final String meetingMeta;

  /// 信息卡徽标文案。
  final String badgeText;

  /// 纪要内容。
  final MinutesView minutes;

  /// 关闭。
  final VoidCallback onClose;

  /// 分享。
  final VoidCallback onShare;

  /// 导出纪要。
  final VoidCallback onExport;

  /// 收藏 / 取消收藏。
  final VoidCallback onFavorite;

  /// 是否已收藏。
  final bool favorited;

  /// 信息卡是否收起（true = 仅小号标题行，给纪要内容让空间）。
  final bool headerCollapsed;

  /// 点击信息卡切换收起/展开（null = 不支持收缩，如设计稿目录页）。
  final VoidCallback? onToggleHeaderCollapse;

  /// 顶部提示（如「终稿处理中 · 完成后自动刷新纪要」）。
  final String? notice;

  /// 提示条动作文案（如「重试」；为 null 时提示条展示转圈）。
  final String? noticeAction;

  /// 提示条动作回调（为 null 时提示条展示转圈）。
  final VoidCallback? onNoticeAction;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      // 只滚动纪要卡内容：顶栏 / 信息卡 / 提示条固定（自行管理滚动）。
      scrollable: false,
      bottomSpacer: 0,
      bottomCta: Row(
        children: <Widget>[
          Expanded(
            child: AppPillButton(label: '导出纪要', onTap: onExport, height: 44),
          ),
          const SizedBox(width: 12),
          AppCircleButton(
            icon: favorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            onTap: onFavorite,
            tooltip: '收藏',
            size: 44,
            iconSize: 17,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTopBar(
            title: '会议纪要',
            subtitle: generatedAt,
            leadingIcon: Icons.close_rounded,
            onLeading: onClose,
            actionIcon: Icons.ios_share_rounded,
            onAction: onShare,
          ),
          // 固定 header：信息卡与提示条不随纪要内容滚动。
          MeetingInfoCard(
            title: meetingTitle,
            meta: meetingMeta,
            badgeText: badgeText,
            // 「查看完整转写」入口（按参考图挂在顶部信息卡内，替代原卡片底部行）。
            transcriptChars: minutes.transcriptChars,
            onOpenTranscript: minutes.onOpenTranscript,
            // header 收缩（用户要求）：点击信息卡收起为小号标题行，给内容让空间。
            collapsed: headerCollapsed,
            onToggleCollapse: onToggleHeaderCollapse,
          ),
          if (notice != null)
            Container(
              margin: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: <Widget>[
                  // 处理中（无动作）才转圈；失败（带动作）展示重试按钮。
                  if (onNoticeAction == null) ...<Widget>[
                    const SizedBox(width: 20, height: 20, child: AppSpinner(size: 12)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      notice!,
                      style: AppTextStyles.metaSmall.copyWith(color: AppColors.orange),
                    ),
                  ),
                  if (onNoticeAction != null && noticeAction != null)
                    TextButton(
                      onPressed: onNoticeAction,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        noticeAction!,
                        style: AppTextStyles.metaSmall.copyWith(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // header 与内容区之间的固定间隔（放滚动区外，滚动时不消失）。
          const SizedBox(height: 16),
          // 仅纪要卡内容滚动（底部留白避开 CTA：手势条 inset + CTA 高度 + 余量）。
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              child: MinutesCard(
                view: minutes,
                // 顶部间距由上方固定 SizedBox 提供，卡片自带 margin 归零。
                margin: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
