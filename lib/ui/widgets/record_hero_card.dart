/// 待机态 Hero 卡（设计稿 01 号屏 / 2:41）。
///
/// 结构：状态行 → 大橙圆 mic（外圈光晕）→ 主文案 → 副文案 → 模式分段控件。
library;

import 'package:flutter/material.dart';

import '../../domain/recording_mode.dart';
import '../theme/app_theme.dart';
import 'segmented_control.dart';

/// Hero 卡。
class RecordHeroCard extends StatelessWidget {
  /// 构造 Hero 卡。
  const RecordHeroCard({
    super.key,
    required this.statusText,
    required this.onStartRecording,
    required this.mode,
    required this.onModeChanged,
    this.title = '点击开始录音',
    this.hint = '中英文自动转写 · 智能区分说话人',
    this.busy = false,
  });

  /// 状态行文案（如「待机中 · 今日已记录 42 分钟」）。
  final String statusText;

  /// 点击麦克风回调。
  final VoidCallback onStartRecording;

  /// 当前模式。
  final RecordingMode mode;

  /// 模式变更回调。
  final ValueChanged<RecordingMode> onModeChanged;

  /// 主文案。
  final String title;

  /// 副文案。
  final String hint;

  /// 是否正在准备（禁用按钮）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.cardLg, AppSpacing.cardLg, AppSpacing.cardLg, AppSpacing.card),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadow.hero,
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusText,
                  style: AppTextStyles.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gapLg),
          _MicButton(onTap: busy ? null : onStartRecording),
          const SizedBox(height: AppSpacing.gapLg),
          Text(title, style: AppTextStyles.heroTitle),
          const SizedBox(height: 6),
          Text(hint, style: AppTextStyles.meta, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.gapLg),
          SegmentedControl<RecordingMode>(
            options: const <SegmentOption<RecordingMode>>[
              SegmentOption<RecordingMode>(value: RecordingMode.meeting, label: '会议'),
              SegmentOption<RecordingMode>(value: RecordingMode.interview, label: '访谈'),
              SegmentOption<RecordingMode>(value: RecordingMode.inspiration, label: '灵感'),
            ],
            value: mode,
            onChanged: onModeChanged,
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '开始录音',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: AppRadius.haloDiameter,
          height: AppRadius.haloDiameter,
          child: Center(
            child: Container(
              width: AppRadius.haloDiameter,
              height: AppRadius.haloDiameter,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: AppRadius.micDiameter,
                  height: AppRadius.micDiameter,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
