/// 屏 15：导入处理中（HTML 设计稿屏 15）。
///
/// 四步卡：①上传 ②分离音轨（视频）/「无需分离」（音频）③语音转写 ④纪要；
/// 角标「视频仅解析音轨，画面内容不参与分析」「原文件不会被修改」（纯静态文案）。
/// 「后台处理」= 顶部按钮 = 返回（处理继续）；「取消处理」= 底部按钮（确认后取消）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/surface_card.dart';
import 'screen_frame.dart';

/// 单步卡视图数据。
class ImportStepView {
  /// 构造步骤卡数据。
  const ImportStepView({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.status,
    this.percent,
    this.skip = false,
  });

  /// 序号（1-4）。
  final int index;

  /// 标题（上传 / 分离音轨 / 语音转写 / 纪要生成）。
  final String title;

  /// 副文案。
  final String subtitle;

  /// 状态（`idle` / `running` / `done` / `failed` / `cancelled` / `skip`）。
  final String status;

  /// 上传进度 0..1（仅步骤 ①）。
  final double? percent;

  /// 是否「无需分离」占位。
  final bool skip;

  /// 主状态文案。
  String get statusLabel => switch (status) {
        'running' => '处理中…',
        'done' => '完成',
        'failed' => '失败',
        'cancelled' => '已取消',
        'skip' => '无需分离',
        _ => '等待中',
      };
}

/// 屏 15 视觉。
class ImportProcessingScreen extends StatelessWidget {
  /// 构造屏 15。
  const ImportProcessingScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isVideo,
    required this.steps,
    required this.detail,
    required this.etaMinutes,
    required this.allDone,
    required this.onBack,
    required this.onCancel,
    required this.onViewMinutes,
    required this.onTabTap,
    this.selectedTab = 0,
  });

  /// 标题（文件名）。
  final String title;

  /// 副标题（来源说明）。
  final String subtitle;

  /// 是否视频（决定步骤 ② 文案与角标）。
  final bool isVideo;

  /// 四步卡数据。
  final List<ImportStepView> steps;

  /// 提示（软警告 / 失败原因）。
  final String? detail;

  /// 预计剩余分钟数（0 = 不显示）。
  final int etaMinutes;

  /// 四步是否全部完成。
  final bool allDone;

  /// 「后台处理」。
  final VoidCallback onBack;

  /// 「取消处理」。
  final VoidCallback onCancel;

  /// 「查看纪要」（完成后）。
  final VoidCallback onViewMinutes;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 选中 Tab。
  final int selectedTab;

  @override
  Widget build(BuildContext context) {
    final bool failed = steps.any((ImportStepView s) => s.status == 'failed' || s.status == 'cancelled');
    return ScreenFrame(
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      scrollable: true,
      bottomSpacer: 120,
      bottomCta: allDone
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppPillButton(label: '查看纪要', onTap: onViewMinutes),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AppGhostPillButton(
                label: failed ? '关闭' : '取消处理',
                icon: Icons.close_rounded,
                onTap: onCancel,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 10, AppSpacing.page, 0),
            child: Row(
              children: <Widget>[
                AppCircleButton(icon: Icons.chevron_left_rounded, onTap: onBack, tooltip: '后台处理'),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        allDone ? '导入完成' : '导入处理中',
                        style: AppTextStyles.cardHead,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        allDone ? '纪要已生成，可前往查看' : '可返回首页或历史页，处理继续',
                        style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
            child: SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: AppTextStyles.itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted)),
                  if (!allDone && etaMinutes > 0) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '预计还需约 $etaMinutes 分钟',
                      style: AppTextStyles.metaSmall.copyWith(color: AppColors.orange),
                    ),
                  ],
                  if (detail != null && detail!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(detail!, style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted)),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Column(
              children: <Widget>[
                for (final ImportStepView step in steps)
                  _StepCard(step: step, isVideo: isVideo),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isVideo)
                  const _NotePill(text: '视频仅解析音轨，画面内容不参与分析'),
                const SizedBox(height: 6),
                const _NotePill(text: '原文件不会被修改'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单步卡（①②③④）。
class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.isVideo});

  final ImportStepView step;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final bool done = step.status == 'done';
    final bool failed = step.status == 'failed' || step.status == 'cancelled';
    final bool running = step.status == 'running';
    final Color circleColor = done
        ? AppColors.orange
        : failed
            ? AppColors.muted
            : AppColors.card;
    final Widget leading = step.skip
        ? Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.horizontal_rule_rounded, size: 16, color: AppColors.muted),
          )
        : Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: circleColor,
              borderRadius: BorderRadius.circular(15),
              boxShadow: done ? AppShadow.circleButton : null,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '${step.index}',
                    style: AppTextStyles.metaSmall.copyWith(
                      color: failed ? Colors.white : AppColors.ink,
                    ),
                  ),
          );
    final Widget trailing = step.skip
        ? Text('无需分离', style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted))
        : running && step.percent != null
            ? Text(
                '${(step.percent!.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.metaSmall.copyWith(color: AppColors.orange),
              )
            : Text(
                step.statusLabel,
                style: AppTextStyles.metaSmall.copyWith(
                  color: failed ? AppColors.muted : (done ? AppColors.orange : AppColors.muted),
                ),
              );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card2),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(step.title, style: AppTextStyles.settingTitle),
                const SizedBox(height: 2),
                if (running && step.percent != null) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: step.percent!.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.muted.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  step.subtitle,
                  style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// 静态角标（「视频仅解析音轨…」「原文件不会被修改」）。
class _NotePill extends StatelessWidget {
  const _NotePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.muted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
      ),
    );
  }
}
