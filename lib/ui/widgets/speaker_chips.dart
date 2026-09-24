/// 说话人 chips：彩色圆点 + 名称。
///
/// 两种用法：
/// - 录音中（02 号屏）：仅展示当前已识别的说话人；
/// - 完整转写（07 号屏）：可选中过滤，含「全部」项（调用方传 [showAll]）。
library;

import 'package:flutter/material.dart';

import '../../domain/speaker.dart';
import '../theme/app_theme.dart';

/// 说话人 chips。
class SpeakerChips extends StatelessWidget {
  /// 构造 chips。
  const SpeakerChips({
    super.key,
    required this.speakers,
    this.selectedId,
    this.onSelected,
    this.showAll = false,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.page),
  });

  /// 说话人表。
  final List<Speaker> speakers;

  /// 当前选中的说话人 ID（null = 未选）。
  final String? selectedId;

  /// 选中回调（回调 null 表示选择「全部」）。
  final ValueChanged<String?>? onSelected;

  /// 是否展示「全部」项。
  final bool showAll;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: <Widget>[
          if (showAll)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: '全部',
                color: AppColors.primary,
                selected: selectedId == null,
                onTap: onSelected == null ? null : () => onSelected!(null),
              ),
            ),
          for (final Speaker speaker in speakers)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: speaker.name,
                color: speakerColor(speaker.colorIndex),
                selected: selectedId == speaker.speakerId,
                onTap: onSelected == null
                    ? null
                    : () => onSelected!(
                        selectedId == speaker.speakerId ? null : speaker.speakerId,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.selected,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? color : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? Colors.transparent : AppColors.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.meta.copyWith(
                    color: selected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 由配色下标取说话人主色（越界回绕）。
Color speakerColor(int colorIndex) {
  const List<Color> palette = AppColors.speakerPalette;
  final int index = colorIndex < 0 ? 0 : colorIndex % palette.length;
  return palette[index];
}

/// 由配色下标取说话人浅底色。
Color speakerSoftColor(int colorIndex) {
  const List<Color> palette = AppColors.speakerSoftPalette;
  final int index = colorIndex < 0 ? 0 : colorIndex % palette.length;
  return palette[index];
}