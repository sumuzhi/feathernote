/// 过滤 chips：`全部 / 今天 / 本周 / 已总结`（选中为橙色实心 pill）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 单个过滤项。
class FilterOption {
  /// 构造过滤项。
  const FilterOption({required this.id, required this.label});

  /// 取值。
  final String id;

  /// 文案。
  final String label;
}

/// 过滤 chips 行。
class FilterChips extends StatelessWidget {
  /// 构造过滤行。
  const FilterChips({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.page),
  });

  /// 可选项。
  final List<FilterOption> options;

  /// 当前选中项。
  final String selectedId;

  /// 选中回调。
  final ValueChanged<String> onSelected;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: <Widget>[
          for (final FilterOption option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterPill(
                label: option.label,
                selected: option.id == selectedId,
                onTap: () => onSelected(option.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.segment),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.segment),
              border: Border.all(
                color: selected ? Colors.transparent : AppColors.hairline,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.meta.copyWith(
                color: selected ? Colors.white : AppColors.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
