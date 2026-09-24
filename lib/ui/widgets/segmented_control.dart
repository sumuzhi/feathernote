/// 分段控件：轨道 + 白底选中 pill（设计稿 01 号屏的 会议 / 访谈 / 灵感）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 分段项。
class SegmentOption<T> {
  /// 构造分段项。
  const SegmentOption({required this.value, required this.label});

  /// 取值。
  final T value;

  /// 文案。
  final String label;
}

/// 分段控件。
class SegmentedControl<T> extends StatelessWidget {
  /// 构造分段控件。
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 44,
  });

  /// 选项。
  final List<SegmentOption<T>> options;

  /// 当前值。
  final T value;

  /// 变更回调（null 时只读）。
  final ValueChanged<T>? onChanged;

  /// 高度。
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.trackSoft,
        borderRadius: BorderRadius.circular(AppRadius.track),
      ),
      child: Row(
        children: <Widget>[
          for (final SegmentOption<T> option in options)
            Expanded(
              child: _SegmentItem(
                label: option.label,
                selected: option.value == value,
                onTap: onChanged == null ? null : () => onChanged!(option.value),
                height: height - 8,
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.segment),
            boxShadow: selected
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x149E8066),
                      offset: Offset(0, 2),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: selected ? AppColors.primary : AppColors.ink2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
