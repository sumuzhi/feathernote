/// 搜索命中条（HTML `.hit-bar`，屏 12）：「找到 12 处「激活」」+ `3 / 12` + 上下切换 + 关闭。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 命中条。
class HitBar extends StatelessWidget {
  /// 构造命中条。
  const HitBar({
    super.key,
    required this.total,
    required this.current,
    required this.keyword,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  /// 命中总数。
  final int total;

  /// 当前命中序号（1-based）。
  final int current;

  /// 关键词。
  final String keyword;

  /// 上一处。
  final VoidCallback onPrev;

  /// 下一处。
  final VoidCallback onNext;

  /// 关闭。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.hitBarBg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '找到 $total 处「$keyword」',
              style: AppTextStyles.meta.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.orange,
              ),
            ),
          ),
          Text(
            '$current / $total',
            style: AppTextStyles.meta.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(width: 8),
          _HitButton(icon: Icons.expand_less_rounded, tooltip: '上一处', onTap: onPrev),
          const SizedBox(width: 6),
          _HitButton(icon: Icons.expand_more_rounded, tooltip: '下一处', onTap: onNext),
          const SizedBox(width: 6),
          _HitButton(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            color: AppColors.closeBrown,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _HitButton extends StatelessWidget {
  const _HitButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(icon, size: 16, color: color ?? AppColors.orange),
          ),
        ),
      ),
    );
  }
}
