/// 搜索框（圆角 21 / 高 42，白底 + 暖色描边）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 搜索框。
class AppSearchField extends StatelessWidget {
  /// 构造搜索框。
  const AppSearchField({
    super.key,
    required this.controller,
    this.hintText = '搜索',
    this.onChanged,
    this.onClear,
  });

  /// 文本控制器。
  final TextEditingController controller;

  /// 占位文案。
  final String hintText;

  /// 变更回调。
  final ValueChanged<String>? onChanged;

  /// 清空回调。
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.body,
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          hintText: hintText,
          hintStyle: AppTextStyles.meta,
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.ink2,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, Widget? child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.ink2),
                tooltip: '清空',
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onClear?.call();
                },
              );
            },
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: _border(AppColors.hairline),
          enabledBorder: _border(AppColors.hairline),
          focusedBorder: _border(AppColors.primary),
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.search),
    borderSide: BorderSide(color: color),
  );
}
