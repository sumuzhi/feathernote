/// 顶部浮动提示条（Toast）。
///
/// **全站统一 toast 样式**（对齐设计规格）：
/// `height 59 / padding 11px 12px / gap 10`，
/// `background #FFF0E3`、`border 1px #F2C9A3`、`radius 14`、
/// `shadow 0 6 16 -4 rgba(158,128,102,.16)`。
/// - [AppToast]：普通提示（info / warning / success 三种语气图标）；
/// - [AppActionToast]：断线重连（同容器 + 右侧重试按钮）。
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

/// 统一 toast 容器装饰（背景 / 边框 / 圆角 / 阴影，全站唯一来源）。
BoxDecoration appToastDecoration() => BoxDecoration(
  color: const Color(0xFFFFF0E3),
  border: Border.all(color: const Color(0xFFF2C9A3)),
  borderRadius: BorderRadius.circular(14),
  boxShadow: const <BoxShadow>[
    BoxShadow(
      color: Color(0x299E8066), // rgba(158,128,102,.16)
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -4,
    ),
  ],
);

/// Toast 文案环境的「归零」默认样式（**双下划线根因修复**）。
///
/// 背景：Toast 浮层挂在 `MaterialApp.builder` 层 —— 位于 Navigator 之外，
/// **没有任何 [Material] 祖先**。此时 [Text] 继承的是 MaterialApp 的错误兜底样式
/// （`_errorTextStyle`：`TextDecoration.underline` + `decorationStyle: double` +
/// 黄色装饰色 + `fontFamily: monospace`）。Toast 自己的样式只覆盖了颜色 / 字号 /
/// 字重，`decoration` 与 `fontFamily` 为 null 时**原样继承**——这就是文案下出现
/// 「黄色双下划线」、且移除打包字体也修不掉的原因（字体只是被冤枉的）。
/// 用本样式包一层 [DefaultTextStyle]，把 decoration / fontFamily 归零为系统默认。
Widget toastTextEnvironment({required Widget child}) => DefaultTextStyle(
  style: const TextStyle(decoration: TextDecoration.none),
  child: child,
);

/// 普通提示条（统一浅橙样式）。
class AppToast extends StatelessWidget {
  /// 构造提示条。
  const AppToast({super.key, required this.message});

  /// 提示内容。
  final ToastMessage message;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (message.tone) {
      ToastTone.info => Icons.info_outline_rounded,
      ToastTone.warning => Icons.wifi_off_rounded,
      ToastTone.success => Icons.check_circle_outline_rounded,
    };
    return toastTextEnvironment(
      child: Container(
        height: 59,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: appToastDecoration(),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 21, color: AppColors.orange),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.text,
                style: AppTextStyles.body15.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
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

/// 断线重连提示条（统一浅橙样式 + 右侧重试按钮）。
class AppActionToast extends StatelessWidget {
  /// 构造重连提示条。
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
    return toastTextEnvironment(
      child: Container(
        height: 59,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: appToastDecoration(),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 34,
              height: 34,
              child: Icon(
                Icons.wifi_off_rounded,
                size: 22,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.settingTitle.copyWith(
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.metaSmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(56, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  actionLabel,
                  style: AppTextStyles.metaSmall.copyWith(color: Colors.white),
                ),
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
  const AppToastOverlay({
    super.key,
    required this.message,
    required this.child,
  });

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
                child: current == null
                    ? const SizedBox.shrink()
                    : AppToast(message: current),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
