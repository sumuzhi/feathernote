/// 按钮：主橙大圆角 CTA + 白底描边次按钮。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 主按钮（橙色实心圆角 pill）。
class AppPrimaryButton extends StatelessWidget {
  /// 构造主按钮。
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = true,
    this.height = 52,
    this.busy = false,
  });

  /// 文案。
  final String label;

  /// 前置图标。
  final IconData? icon;

  /// 点击回调（null = 禁用）。
  final VoidCallback? onPressed;

  /// 是否占满宽度。
  final bool expanded;

  /// 高度。
  final double height;

  /// 是否处于忙碌态（显示进度圈并禁用）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Widget button = SizedBox(
      height: height,
      width: expanded ? double.infinity : null,
      child: Material(
        color: onPressed == null ? AppColors.dot : AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.cta),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else if (icon != null)
                  Icon(icon, size: 18, color: Colors.white),
                if (busy || icon != null) const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.button.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(button: true, enabled: onPressed != null, child: button);
  }
}

/// 次按钮（白底 + 暖色描边 pill）。
class AppGhostButton extends StatelessWidget {
  /// 构造次按钮。
  const AppGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
    this.height = 52,
  });

  /// 文案。
  final String label;

  /// 前置图标。
  final IconData? icon;

  /// 点击回调。
  final VoidCallback? onPressed;

  /// 是否占满宽度。
  final bool expanded;

  /// 高度。
  final double height;

  @override
  Widget build(BuildContext context) {
    final Widget button = SizedBox(
      height: height,
      width: expanded ? double.infinity : null,
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: AppColors.ink),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTextStyles.buttonGhost,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(button: true, enabled: onPressed != null, child: button);
  }
}

/// 圆形图标按钮（书签 FAB 等）。
class AppIconFab extends StatelessWidget {
  /// 构造图标 FAB。
  const AppIconFab({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.filled = false,
    this.size = 52,
  });

  /// 图标。
  final IconData icon;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 无障碍提示。
  final String? tooltip;

  /// 是否橙色实心（否则白底描边）。
  final bool filled;

  /// 直径。
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget fab = Material(
      color: filled ? AppColors.primary : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: filled ? Colors.transparent : AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: 20,
            color: filled ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
    if (tooltip == null) return fab;
    return Tooltip(message: tooltip!, child: fab);
  }
}
