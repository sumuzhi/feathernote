/// 说话人 chip（HTML `.sp-chip`）与说话人序号头像。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/speaker_palette.dart';

/// 说话人 chip 视图数据。
class SpeakerChipView {
  /// 构造 chip 数据。
  const SpeakerChipView({
    required this.ordinal,
    required this.label,
    this.gray = false,
  });

  /// 说话人序号（1-based）。
  final int ordinal;

  /// 文案（如「说话人 1」或「说话人 8 · 识别中」）。
  final String label;

  /// 灰态（识别中 / 未确认，HTML `.sp-chip.gray`）。
  final bool gray;
}

/// 说话人 chip。
class SpeakerChip extends StatelessWidget {
  /// 构造 chip。
  const SpeakerChip({super.key, required this.view});

  /// chip 数据。
  final SpeakerChipView view;

  @override
  Widget build(BuildContext context) {
    final Color background = view.gray ? AppColors.grayWash : speakerSoftColor(view.ordinal);
    final Color foreground = view.gray ? AppColors.faint : speakerColor(view.ordinal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: view.gray ? speakerPaletteAt(view.ordinal - 1).foreground : foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(view.label, style: AppTextStyles.speakerChip.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// 横向可换行的说话人 chip 组（HTML `.sp-chips`）。
class SpeakerChipRow extends StatelessWidget {
  /// 构造 chip 组。
  const SpeakerChipRow({super.key, required this.items});

  /// chip 列表。
  final List<SpeakerChipView> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 18, AppSpacing.page, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final SpeakerChipView item in items) SpeakerChip(view: item),
        ],
      ),
    );
  }
}

/// 说话人序号圆形头像（HTML `.t-avatar`，28×28）。
class SpeakerAvatar extends StatelessWidget {
  /// 构造头像。
  const SpeakerAvatar({super.key, required this.ordinal});

  /// 说话人序号（1-based）。
  final int ordinal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: speakerColor(ordinal),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$ordinal',
        style: AppTextStyles.chip.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
