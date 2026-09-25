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
                child: Text(title, style: AppTextStyles.cardTitle),
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

/// 「查看完整转写」入口行（浅橙圆角行 + 文档图标 + 字数 ›）。
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.orangeWash,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.description_rounded,
                size: 18,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('查看完整转写', style: AppTextStyles.subHead)),
            Text(
              chars,
              style: AppTextStyles.meta.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
