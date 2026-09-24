/// 顶部浮动提示条（Toast）。
///
/// 对应设计稿 2:546 的「录音中 · 断线重连」提示：白底 / 暖色描边胶囊，
/// 左侧图标 + 单行文案，从顶部滑入。用于断线重连、书签、错误等瞬时反馈。
///
/// 本文件只负责**视觉**；显示/自动消失的调度在
/// `lib/ui/providers/app_providers.dart` 的 `toastProvider`。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
class ToastMessage {
  /// 构造提示。
  const ToastMessage({
    required this.text,
    this.tone = ToastTone.info,
    this.sticky = false,
    this.duration = const Duration(seconds: 3),
    this.nonce = 0,
  });

  /// 文案。
  final String text;

  /// 语气。
  final ToastTone tone;

  /// 是否常驻（需显式清除，如「正在重连…」）。
  final bool sticky;

  /// 自动消失时长。
  final Duration duration;

  /// 递增序号：同文案再次弹出时也能触发动画（`==` 因此不同）。
  final int nonce;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToastMessage &&
          other.text == text &&
          other.tone == tone &&
          other.sticky == sticky &&
          other.duration == duration &&
          other.nonce == nonce;

  @override
  int get hashCode => Object.hash(text, tone, sticky, duration, nonce);
}

/// 单条提示的视觉。
class AppToast extends StatelessWidget {
  /// 构造提示条。
  const AppToast({super.key, required this.message});

  /// 提示内容。
  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color accent) = switch (message.tone) {
      ToastTone.info => (Icons.bookmark_added_outlined, AppColors.primary),
      ToastTone.warning => (Icons.wifi_off_rounded, AppColors.primaryDeep),
      ToastTone.success => (Icons.check_circle_outline_rounded, AppColors.speakerGreen),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTap),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppShadow.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message.text,
                style: AppTextStyles.meta.copyWith(color: AppColors.ink),
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
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 0),
              child: IgnorePointer(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: current == null ? const Offset(0, -1.4) : Offset.zero,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: current == null ? 0 : 1,
                    child: Center(
                      child: current == null
                          ? const SizedBox.shrink()
                          : AppToast(message: current),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
