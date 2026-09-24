/// 转写片段条目（HTML `.t-item`）。
///
/// 三种变体：
/// - 普通：圆形序号头像 + 「说话人 N · 时间」+ 正文；
/// - `pending`：半透明（0.55）+ 正文转灰，用于「待上传」（s06）；
/// - `highlight`：浅橙底圆角卡 + 「展开这段 · N 字」（s12）。
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
    this.pending = false,
    this.highlight = false,
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

  /// 待上传态（HTML `.t-item.pending`）。
  final bool pending;

  /// 命中高亮态（HTML `.t-item.hl`）。
  final bool highlight;

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
  });

  /// 条目数据。
  final TranscriptItemView item;

  /// 是否显示「· 时间」。
  final bool showTime;

  /// 点击「展开这段」的回调。
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final Color accent = speakerColor(item.ordinal);
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
                RichText(
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
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
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
                        Text(item.expandNote!, style: AppTextStyles.action.copyWith(fontSize: 13)),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 13, color: AppColors.orange),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.hitBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: content,
    );
  }
}
