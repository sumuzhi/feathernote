/// 过滤 chip（HTML `.chip`）：白底 → 选中橙色胶囊。
///
/// 用于历史页的「全部 / 今天 / 本周 / 已总结」与转写页的说话人过滤。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/speaker_palette.dart';

/// 过滤 chip 数据。
class FilterChipView {
  /// 构造 chip 数据。
  const FilterChipView({
    required this.label,
    this.ordinal,
    this.selected = false,
  });

  /// 文案。
  final String label;

  /// 说话人序号（有值时在文字前显示对应色点）。
  final int? ordinal;

  /// 是否选中。
  final bool selected;
}

/// 单个过滤 chip。
class FilterChip extends StatelessWidget {
  /// 构造 chip。
  const FilterChip({super.key, required this.view, required this.onTap});

  /// chip 数据。
  final FilterChipView view;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool selected = view.selected;
    final Color foreground = selected ? Colors.white : AppColors.muted;
    Color? dotColor;
    if (view.ordinal != null && !selected) {
      dotColor = speakerColor(view.ordinal!);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: view.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: selected ? AppShadow.chipOn : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (dotColor != null) ...<Widget>[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                view.label,
                style: AppTextStyles.chip.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横向一排过滤 chip（HTML `.filter-row` / `.tr-chips`）。
class FilterChipRow extends StatelessWidget {
  /// 构造 chip 排。
  const FilterChipRow({
    super.key,
    required this.items,
    required this.onTap,
    this.scrollable = false,
    this.enabled = true,
  });

  /// chip 列表。
  final List<FilterChipView> items;

  /// 点击回调（回传下标）。
  final ValueChanged<int> onTap;

  /// 是否横向滚动（转写页 `.tr-chips` 为可滚动）。
  final bool scrollable;

  /// 是否可用（历史空态 s08 为半透明禁用）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget row = scrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Row(children: _children()),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 15, AppSpacing.page, 0),
            child: Row(children: _children()),
          );
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: IgnorePointer(ignoring: !enabled, child: row),
    );
  }

  List<Widget> _children() {
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      children.add(
        FilterChip(view: items[i], onTap: () => onTap(i)),
      );
      if (i != items.length - 1) children.add(const SizedBox(width: 9));
    }
    return children;
  }
}
