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
  });

  /// 会议标题。
  final String title;

  /// 元信息（如「32 分钟 · 3 位说话人 · 今天 09:12」）。
  final String meta;

  /// 徽标文案。
  final String badgeText;

  /// 徽标语义。
  final AppBadgeTone badgeTone;

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
        ],
      ),
    );
  }
}
