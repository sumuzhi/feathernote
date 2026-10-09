/// 转写片段条目（HTML `.t-item`）。
///
/// 三种变体：
/// - 普通：圆形序号头像 + 「说话人 N · 时间」+ 正文；
/// - `pending`：半透明（0.55）+ 正文转灰，用于「待上传」（s06）；
/// - `highlight`：浅橙底圆角卡 + 「展开这段 · N 字」（s12）。
///
/// 播放按钮（对齐设计稿）：
/// - 未播放：说话人**浅底色圆形** + 同色实心三角 ▶，紧跟时间戳；
/// - 播放中：说话人**同色实心圆** + 白色暂停图标 + 段内进度条 + `已播 / 段长`。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/speaker_palette.dart';
import 'speaker_chips.dart';

/// 转写条目视图数据。
class TranscriptItemView {
  /// 构造条目。
  const TranscriptItemView({
    required this.ordinal,
    required this.speakerLabel,
    required this.timeLabel,
    required this.text,
    required this.segmentId,
    required this.startTimeMs,
    required this.endTimeMs,
    this.pending = false,
    this.highlight = false,
    this.playActive = false,
    this.isPlaying = false,
    this.playProgress = 0,
    this.playPositionLabel = '',
    this.playDurationLabel = '',
    this.expandNote,
  });

  /// 说话人序号（1-based，决定头像与姓名的配色）。
  final int ordinal;

  /// 说话人展示名（如「说话人 1」）。
  final String speakerLabel;

  /// 时间文案（如「00:12」，待上传时为「待上传」）。
  final String timeLabel;

  /// 正文。
  final String text;

  /// 片段 ID（用于播放状态关联）。
  final String segmentId;

  /// 开始时间（毫秒，用于 seek）。
  final int startTimeMs;

  /// 结束时间（毫秒，用于自动停）。
  final int endTimeMs;

  /// 待上传态（HTML `.t-item.pending`）。
  final bool pending;

  /// 命中高亮态（HTML `.t-item.hl`）。
  final bool highlight;

  /// 该段是否为「当前段」（正在播放**或已暂停停在该段**）→ 展示进度条与时间。
  final bool playActive;

  /// 是否正在播放（决定按钮显示暂停图标还是播放图标）。
  final bool isPlaying;

  /// 段内播放进度（0–1；仅播放中有意义）。
  final double playProgress;

  /// 段内已播时长文案（如「00:03」；仅播放中有意义）。
  final String playPositionLabel;

  /// 段总时长文案（如「00:08」；仅播放中有意义）。
  final String playDurationLabel;

  /// 「展开这段 · N 字」文案（仅高亮态使用）。
  final String? expandNote;
}

/// 转写条目。
class TranscriptTile extends StatelessWidget {
  /// 构造条目。
  const TranscriptTile({
    super.key,
    required this.item,
    this.showTime = true,
    this.onExpand,
    this.onPlay,
  });

  /// 条目数据。
  final TranscriptItemView item;

  /// 是否显示「· 时间」。
  final bool showTime;

  /// 点击「展开这段」的回调。
  final VoidCallback? onExpand;

  /// 点击播放按钮的回调。
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final Color accent = speakerColor(item.ordinal);
    final Color soft = speakerSoftColor(item.ordinal);
    final bool canPlay = onPlay != null && showTime && !item.pending;

    final Widget body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SpeakerAvatar(ordinal: item.ordinal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: GestureDetector(
                        onTap: canPlay ? onPlay : null,
                        behavior: HitTestBehavior.opaque,
                        // maxLines=1 + 省略：发言人名超长时收缩省略，
                        // 保证播放态整行（发言人/按钮/进度条/时间）不折行。
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: AppTextStyles.meta.copyWith(
                              fontWeight: FontWeight.w600,
                              color: accent,
                              height: 1.3,
                            ),
                            children: <TextSpan>[
                              TextSpan(text: item.speakerLabel),
                              if (showTime)
                                TextSpan(
                                  text: ' · ${item.timeLabel}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (canPlay) ...<Widget>[
                      const SizedBox(width: 8),
                      _PlayButton(
                        accent: accent,
                        soft: soft,
                        isPlaying: item.isPlaying,
                        onTap: onPlay,
                      ),
                      if (item.playActive) ...<Widget>[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SegmentProgressBar(
                            progress: item.playProgress.clamp(0.0, 1.0),
                            accent: accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.playPositionLabel} / ${item.playDurationLabel}',
                          // 设计规格：11px / w400 / #8B7565（AppColors.muted），字体跟随系统。
                          style: AppTextStyles.meta.copyWith(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.text,
                  style: AppTextStyles.body.copyWith(
                    color: item.pending ? AppColors.muted : AppColors.body,
                  ),
                ),
                if (item.highlight && item.expandNote != null) ...<Widget>[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.expandNote!,
                          style: AppTextStyles.action.copyWith(fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 13,
                          color: AppColors.orange,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final Widget content = Opacity(
      opacity: item.pending ? 0.55 : 1,
      child: body,
    );

    if (!item.highlight) {
      return content;
    }
    // 用户反馈「提示不明显」：高亮卡加强为浅橙底 + 橙色描边 + 左侧橙条。
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.hitBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0x80F0783C), width: 1.2),
      ),
      child: content,
    );
  }
}

/// 播放按钮（对齐设计稿）。
///
/// - 未播放：说话人**浅底色圆形** + 同色实心三角 ▶；
/// - 播放中：说话人**同色实心圆** + 白色暂停图标（两竖条）。
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.accent,
    required this.soft,
    required this.isPlaying,
    required this.onTap,
  });

  final Color accent;
  final Color soft;
  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const double size = 26;

    final Widget icon = isPlaying
        ? SizedBox(
            width: 9,
            height: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _pauseBar(),
                const SizedBox(width: 3),
                _pauseBar(),
              ],
            ),
          )
        : Icon(Icons.play_arrow_rounded, size: 16, color: accent);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: isPlaying ? accent : soft, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: icon,
      ),
    );
  }

  Widget _pauseBar() => Container(
        width: 2.5,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// 段内播放进度条：同色已播 + 浅色轨道（圆角胶囊）。
///
/// 平滑性：位置流约 200ms 一跳，直接按 `widthFactor` 渲染会出现
/// 「停顿—瞬跳」的顿挫感。这里用 [TweenAnimationBuilder] 在两次更新之间
/// 线性插值（320ms，略长于回调间隔），视觉上连续推进，不再卡顿 / 后腿。
class _SegmentProgressBar extends StatelessWidget {
  const _SegmentProgressBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final double target = progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      duration: const Duration(milliseconds: 320),
      curve: Curves.linear,
      builder: (BuildContext context, double value, Widget? _) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: <Widget>[
              Container(color: AppColors.grayWash),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
