/// 加载指示器：胶囊形「分段加载中」（HTML `.seg-load`）与贴在截断卡下方的
/// 「正在加载更多」（HTML `.load-more`）。
///
/// 旋转指示器尊重「减少动效」：开启后改为静态圆环。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 旋转指示器（14×14，橙色描边、顶部缺口）。
class AppSpinner extends StatefulWidget {
  /// 构造指示器。
  const AppSpinner({super.key, this.size = 14});

  /// 尺寸。
  final double size;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget ring = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.orange, width: 2),
      ),
    );
    if (reduceMotion) {
      return SizedBox(width: widget.size, height: widget.size, child: ring);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: Stack(
          children: <Widget>[
            ring,
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: widget.size,
                height: 2,
                color: AppColors.bg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊形加载提示（HTML `.seg-load`）：高 42，圆角 999。
class AppSegmentedLoadingPill extends StatelessWidget {
  /// 构造提示。
  const AppSegmentedLoadingPill({super.key, required this.text});

  /// 文案（如「分段加载中 · 已显示 1,240 / 3,480 段」）。
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const AppSpinner(),
          const SizedBox(width: 7),
          Text(text, style: AppTextStyles.metaSmall),
        ],
      ),
    );
  }
}

/// 贴在截断卡下方的「正在加载更多」（HTML `#s09 .load-more`）。
class AppLoadMore extends StatelessWidget {
  /// 构造提示。
  const AppLoadMore({super.key, required this.text});

  /// 文案（如「正在加载更多 · 已显示 24 / 128」）。
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.card2),
          bottomRight: Radius.circular(AppRadius.card2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const AppSpinner(),
          const SizedBox(width: 7),
          Text(text, style: AppTextStyles.metaSmall.copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}
