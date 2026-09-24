/// 历史卡片（设计稿 04 号屏 / 2:311）。
///
/// 结构：标题 + 说话人占位头像点 + 更多菜单 → 纪要预览一行 → 元信息 + 徽标。
library;

import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_badge.dart';
import 'surface_card.dart';

/// 历史卡片。
class HistoryCard extends StatelessWidget {
  /// 构造历史卡片。
  const HistoryCard({
    super.key,
    required this.summary,
    this.onTap,
    this.onRename,
    this.onDelete,
    this.now,
  });

  /// 历史列表项。
  final MeetingSummary summary;

  /// 点击进入详情。
  final VoidCallback? onTap;

  /// 重命名。
  final VoidCallback? onRename;

  /// 删除。
  final VoidCallback? onDelete;

  /// 注入「现在」（便于单测）。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final String excerpt = summary.minutesExcerpt.isNotEmpty
        ? summary.minutesExcerpt
        : _fallbackExcerpt(summary);
    return SurfaceCard(
      radius: AppRadius.history,
      padding: const EdgeInsets.all(AppSpacing.cardSm),
      onTap: onTap,
      semanticLabel: '${summary.title}，${formatHistoryMeta(durationMs: summary.durationMs, createdAt: summary.createdAt, now: now)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  summary.title,
                  style: AppTextStyles.itemTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (summary.speakerCount > 0) ...<Widget>[
                const SizedBox(width: 8),
                _AvatarDots(count: summary.speakerCount),
              ],
              if (onRename != null || onDelete != null)
                _MoreMenu(onRename: onRename, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            excerpt,
            style: AppTextStyles.meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.gapSm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${formatHistoryMeta(durationMs: summary.durationMs, createdAt: summary.createdAt, now: now)}'
                  '${summary.speakerCount > 0 ? ' · ${formatPeople(summary.speakerCount)}' : ''}',
                  style: AppTextStyles.metaSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(summary: summary),
            ],
          ),
        ],
      ),
    );
  }

  String _fallbackExcerpt(MeetingSummary summary) {
    if (summary.hasMinutes) return '纪要已生成，点击查看';
    if (summary.status == MeetingStatus.recording) return '录音未结束';
    if (summary.finalizeStatus == FinalizeStatus.pending) return '正在生成终稿转写…';
    if (summary.finalizeStatus == FinalizeStatus.failed) return '终稿转写失败，可重新生成';
    if (summary.minutesPartial) return '纪要生成中断，可继续生成';
    return '暂无纪要';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.summary});

  final MeetingSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.hasMinutes) {
      return const AppBadge(label: '已总结', tone: BadgeTone.orange);
    }
    if (summary.minutesPartial) {
      return const AppBadge(label: '生成中断', tone: BadgeTone.orange);
    }
    if (summary.finalizeStatus == FinalizeStatus.pending ||
        summary.status == MeetingStatus.recording) {
      return const AppBadge(label: '处理中', tone: BadgeTone.slate);
    }
    return const AppBadge(label: '已完成', tone: BadgeTone.green);
  }
}

class _AvatarDots extends StatelessWidget {
  const _AvatarDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final int shown = count > 3 ? 3 : count;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < shown; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.avatarDot,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({this.onRename, this.onDelete});

  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.ink2),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.infoBar),
      ),
      onSelected: (String value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (onRename != null)
          const PopupMenuItem<String>(
            value: 'rename',
            height: 44,
            child: Text('重命名', style: AppTextStyles.meta),
          ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Text(
              '删除',
              style: AppTextStyles.meta.copyWith(color: AppColors.recRed),
            ),
          ),
      ],
    );
  }
}
