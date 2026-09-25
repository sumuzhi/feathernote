/// 顶部浮动提示条（Toast）。
///
/// 对齐 HTML 的两种形态：
/// - `.toast`（浅橙底 `#FBE3D2` + 橙色文案 + 右侧重试按钮）：断线重连（s06）；
/// - `.toast.plain`（深棕底 `#3A2A20` + 白字）：导出 / 分享 / 复制后的瞬时反馈，
///   HTML JS 里约 2.2s 自动消失。
///
/// 本文件只负责**视觉**；显示/自动消失的调度在
/// `lib/ui/providers/app_providers.dart` 的 `toastProvider`。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// **全局统一的 Toast 显示时长（3 秒）**。
///
/// 产品约定：所有提示一律「显示 3 秒后自动消失」，不允许任何调用点覆盖。
/// 为从结构上保证这一点，`ToastController.show()` **不再暴露** duration / sticky
/// 参数（见 `app_providers.dart`），本常量是唯一时长来源。
const Duration kToastDuration = Duration(seconds: 3);

/// 提示语气。
enum ToastTone {
  /// 中性信息（如「已添加书签」）。
  info,

  /// 警示（如断线重连、生成中断）。
  warning,

  /// 成功（如「已保存」）。
  success,
}

/// 提示内容。
///
/// **不携带 duration / sticky**：所有 toast 一律 [kToastDuration]（3 秒）自动消失，
/// 由 `ToastController.show()` 统一调度 —— 调用点无法覆盖时长或改为常驻。
class ToastMessage {
  /// 构造提示。
  const ToastMessage({
    required this.text,
    this.tone = ToastTone.info,
    this.nonce = 0,
  });

  /// 文案。
  final String text;

  /// 语气。
  final ToastTone tone;

  /// 递增序号：同文案再次弹出时也能触发动画（`==` 因此不同）。
  final int nonce;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToastMessage &&
          other.text == text &&
          other.tone == tone &&
          other.nonce == nonce;

  @override
  int get hashCode => Object.hash(text, tone, nonce);
}

/// 普通提示条（深色底，对齐 HTML `.toast.plain`）。
class AppToast extends StatelessWidget {
  /// 构造提示条。
  const AppToast({super.key, required this.message});

  /// 提示内容。
  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (message.tone) {
      ToastTone.info => Icons.bookmark_added_outlined,
      ToastTone.warning => Icons.wifi_off_rounded,
      ToastTone.success => Icons.check_circle_outline_rounded,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.toastPlain,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadow.toast,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message.text,
                style: AppTextStyles.body15.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 断线重连提示条（浅橙底 + 重试按钮，对齐 HTML `.toast`）。
class AppActionToast extends StatelessWidget {
  /// 构造提示条。
  const AppActionToast({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  /// 主文案。
  final String title;

  /// 副文案。
  final String subtitle;

  /// 右侧按钮文案。
  final String actionLabel;

  /// 右侧按钮回调。
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.toastBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadow.toast,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 34,
              height: 34,
              child: Icon(Icons.wifi_off_rounded, size: 22, color: AppColors.orange),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTextStyles.body15.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.metaSmall.copyWith(color: AppColors.toastSub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(64, 38),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(actionLabel, style: AppTextStyles.settingTitle.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部浮层宿主：把 [child] 与提示浮层组合（放在页面最外层使用）。
///
/// [message] 为 null 时提示滑出并淡出。
class AppToastOverlay extends StatelessWidget {
  /// 构造浮层宿主。
  const AppToastOverlay({super.key, required this.message, required this.child});

  /// 当前提示（null = 不显示）。
  final ToastMessage? message;

  /// 页面内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ToastMessage? current = message;
    // 顶部偏移跟随**系统**状态栏高度（不再使用设计稿里的 47px 假状态栏）。
    final double topInset = MediaQuery.viewPaddingOf(context).top;
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: topInset + 13,
          left: AppSpacing.page,
          right: AppSpacing.page,
          child: IgnorePointer(
            ignoring: current == null,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 350),
              curve: const Cubic(0.2, 0.9, 0.3, 1.2),
              offset: current == null ? const Offset(0, -1.4) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: current == null ? 0 : 1,
                child: current == null ? const SizedBox.shrink() : AppToast(message: current),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
