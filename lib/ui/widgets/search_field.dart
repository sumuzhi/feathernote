/// 搜索框（HTML `.searchbar`）：高 48、圆角 999、白底卡片阴影。
///
/// 支持三态：
/// - 普通；
/// - 聚焦（2px 橙色描边，HTML `.searchbar.focus` / `#s10`）；
/// - 禁用（半透明，HTML `#s08 .searchbar`）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 搜索框。
class SearchField extends StatelessWidget {
  /// 构造搜索框。
  const SearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.focused = false,
    this.enabled = true,
    this.onChanged,
    this.onClear,
  });

  /// 占位文案。
  final String hintText;

  /// 文本控制器（为空时展示纯静态外观）。
  final TextEditingController? controller;

  /// 是否显示为聚焦态（橙色描边）。
  final bool focused;

  /// 是否可用（false 时整体半透明且不可输入）。
  final bool enabled;

  /// 输入回调。
  final ValueChanged<String>? onChanged;

  /// 点击清除按钮回调（为空则不展示清除按钮）。
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final Widget field = Container(
      height: AppSpacing.searchBar,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadow.card,
        border: focused
            ? Border.all(color: AppColors.orange, width: 2)
            : null,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 17, color: enabled ? AppColors.faint : AppColors.disabled),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
              style: AppTextStyles.input,
              cursorColor: AppColors.orange,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: AppTextStyles.input.copyWith(
                  color: enabled ? AppColors.faint : AppColors.disabled,
                ),
              ),
            ),
          ),
          if (onClear != null) ...<Widget>[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD9CDBF),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: IgnorePointer(ignoring: !enabled, child: field),
      ),
    );
  }
}
