/// 会议信息卡（设计稿 11 号屏 / 2:953）：标题 + 状态徽标 + 一行元信息。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_badge.dart';
import 'surface_card.dart';

/// 会议信息卡。
class MeetingInfoCard extends StatelessWidget {
  /// 构造信息卡。
  const MeetingInfoCard({
    super.key,
    required this.title,
    required this.meta,
    this.badgeLabel,
    this.badgeTone = BadgeTone.green,
  });

  /// 会议标题。
  final String title;

  /// 元信息行（如「3 小时 12 分钟 · 8 位说话人 · 今天 09:12」）。
  final String meta;

  /// 徽标文案。
  final String? badgeLabel;

  /// 徽标色调。
  final BadgeTone badgeTone;

  @override
  Widget build(BuildContext context) {
    final String? badge = badgeLabel;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.cardSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.itemTitle.copyWith(fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: 8),
                AppBadge(label: badge, tone: badgeTone),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(meta, style: AppTextStyles.meta),
        ],
      ),
    );
  }
}
