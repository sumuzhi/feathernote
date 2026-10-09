/// 会议信息卡（HTML `#s03 .info` / `#s11 .info`）：标题 + 徽标 + 元信息。
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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 18, AppSpacing.page, 0),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
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
