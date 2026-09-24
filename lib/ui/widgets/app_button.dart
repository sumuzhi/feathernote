/// 按钮族（对齐 HTML 的手写按钮样式）。
///
/// - [AppCircleButton]：44×44 白色圆形图标按钮（HTML `.btn-circle`）；
/// - [AppPillButton]：高 56 橙色胶囊主按钮（HTML `.rec-ctrl .stop` / `.doc-cta .main`）；
/// - [AppGhostPillButton]：高 56 白色胶囊次按钮（HTML `.tr-cta .b1`）；
/// - [AppEmptyCtaButton]：高 50 橙色胶囊空态 CTA（HTML `.empty-hero .cta`）；
/// - [AppTextPillButton]：高 44 胶囊文字按钮（HTML `.empty-hero .acts`）。
///
/// 全部点击区 ≥44。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 白色圆形图标按钮（44×44）。
class AppCircleButton extends StatelessWidget {
  /// 构造按钮。
  const AppCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.iconSize = 18,
    this.orange = false,
  });

  /// 图标。
  final IconData icon;

  /// 点击回调。
  final VoidCallback onTap;

  /// 无障碍标签。
  final String? tooltip;

  /// 直径（默认 44）。
  final double size;

  /// 图标尺寸。
  final double iconSize;

  /// 是否改为橙色底白图标（s10 的筛选按钮）。
  final bool orange;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: orange ? AppColors.orange : AppColors.card,
            shape: BoxShape.circle,
            boxShadow: orange ? AppShadow.avatar : AppShadow.circleButton,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: iconSize,
            color: orange ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// 橙色胶囊主按钮（高 56）。
class AppPillButton extends StatelessWidget {
  /// 构造按钮。
  const AppPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.stopIcon = false,
    this.expand = true,
  });

  /// 文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;

  /// 是否在文字前显示白色方点（「结束并生成」按钮）。
  final bool stopIcon;

  /// 是否占满剩余宽度。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (stopIcon) ...<Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
        ],
        Text(label, style: AppTextStyles.button),
      ],
    );
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          width: expand ? double.infinity : null,
          padding: expand ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadow.orangeButton,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// 白色胶囊次按钮（高 56，HTML `.tr-cta .b1`）。
class AppGhostPillButton extends StatelessWidget {
  /// 构造按钮。
  const AppGhostPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  /// 文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;

  /// 前置图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadow.card,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: AppColors.ink),
                  const SizedBox(width: 8),
                ],
                Text(label, style: AppTextStyles.buttonSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空态橙色 CTA（高 50，HTML `.empty-hero .cta`）。
class AppEmptyCtaButton extends StatelessWidget {
  /// 构造按钮。
  const AppEmptyCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.mic_rounded,
  });

  /// 文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;

  /// 前置图标。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadow.emptyCta,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.body15.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 胶囊文字按钮（高 44，HTML `.empty-hero .acts .b1/.b2`）。
class AppTextPillButton extends StatelessWidget {
  /// 构造按钮。
  const AppTextPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.soft = false,
  });

  /// 文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;

  /// 是否使用浅橙底 + 橙字（`.b2`）。
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: soft ? AppColors.orangeSoft : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: soft ? null : AppShadow.card,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.action.copyWith(
              fontSize: 14,
              color: soft ? AppColors.orange : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
