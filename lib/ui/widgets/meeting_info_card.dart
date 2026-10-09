/// 会议信息卡（HTML `#s03 .info` / `#s11 .info`）：标题 + 徽标 + 元信息。
///
/// 支持收起态（用户要求）：点击信息卡收起 → 仅显示小号标题 + 展开箭头，
/// 为纪要内容让出空间；再点展开还原。整卡点击触发，卡内「查看完整转写」
/// 入口命中测试优先、不会误触收缩。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_badge.dart';

/// 会议信息卡。
class MeetingInfoCard extends StatelessWidget {
  /// 构造信息卡。
  const MeetingInfoCard({
    super.key,
    required this.title,
    required this.meta,
    this.badgeText = '已完成',
    this.badgeTone = AppBadgeTone.done,
    this.transcriptChars,
    this.onOpenTranscript,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  /// 会议标题。
  final String title;

  /// 元信息（如「32 分钟 · 3 位说话人 · 今天 09:12」）。
  final String meta;

  /// 徽标文案。
  final String badgeText;

  /// 徽标语义。
  final AppBadgeTone badgeTone;

  /// 「查看完整转写」右侧字数（如「1,860 字 ›」）。
  ///
  /// 仅当 [onOpenTranscript] 非 null 时展示入口行（空态 / 生成中不出现死入口）。
  final String? transcriptChars;

  /// 点击「查看完整转写」。
  final VoidCallback? onOpenTranscript;

  /// 是否收起（true = 仅小号标题行）。
  final bool collapsed;

  /// 点击切换收起/展开（null = 不支持收缩，保持原静态形态）。
  final VoidCallback? onToggleCollapse;

  BoxDecoration _decoration() => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      );

  EdgeInsets get _margin => const EdgeInsets.fromLTRB(AppSpacing.page, 18, AppSpacing.page, 0);

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleCollapse,
        child: Container(
          margin: _margin,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: _decoration(),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  // 收起态用小一号的历史卡标题（17/w600），给内容区让空间。
                  style: AppTextStyles.itemTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 整卡点击收起；「查看完整转写」入口的内层 GestureDetector 命中优先，
      // 不会误触。onToggleCollapse 为 null（不支持收缩）时无响应。
      onTap: onToggleCollapse,
      child: AnimatedSize(
        duration: AppDuration.fade,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Container(
          margin: _margin,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: _decoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppBadge(text: badgeText, tone: badgeTone),
                  // 收起入口提示（支持收缩时才显示）。
                  if (onToggleCollapse != null) ...<Widget>[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 9),
              Text(meta, style: AppTextStyles.meta),
              if (onOpenTranscript != null) ...<Widget>[
                const SizedBox(height: 12),
                _TranscriptEntry(
                  chars: transcriptChars ?? '',
                  onTap: onOpenTranscript!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「查看完整转写」入口行。
///
/// 视觉规格（对齐设计稿 CSS）：
/// `height: 41px; padding: 11px 14px; display: flex;
///  justify-content: space-between; align-items: center;`
class _TranscriptEntry extends StatelessWidget {
  const _TranscriptEntry({required this.chars, required this.onTap});

  final String chars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 41,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        // 自适应：左组 Expanded（标题超长省略），字数右贴边；任意屏宽不溢出。
        // 垂直不用 padding 撑（41-11×2=19px 太紧，大字体下会纵向溢出），
        // 改用 alignment.center 垂直居中。
        alignment: Alignment.center,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.description_rounded,
                    size: 18,
                    color: AppColors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '查看完整转写',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.settingTitle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              chars,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.meta.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
