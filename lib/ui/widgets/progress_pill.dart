/// 加载指示器：胶囊形「分段加载中」（HTML `.seg-load`）与贴在截断卡下方的
/// 「正在加载更多」（HTML `.load-more`）。
///
/// 旋转指示器尊重「减少动效」：开启后改为静态圆环。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 旋转指示器（14×14，橙色圆弧）。
///
/// 历史缺陷：旧实现是「圆环 + 顶部缺口条」整体旋转，圆环转动本身不可见、
/// 缺口条又像一枚独立的"指针 icon"，视觉上成了**两层各自在转**。
/// 现改为单一旋转元素：一段固定扫过角度的橙色圆弧绕中心旋转，只转一层。
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
    if (reduceMotion) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _ArcSpinnerPainter()),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(painter: _ArcSpinnerPainter()),
      ),
    );
  }
}

/// 单段圆弧：只画一次、只由外层 [RotationTransition] 旋转，绝无第二层动画。
class _ArcSpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - 2) / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // 从 12 点方向起笔
      4.71239, // 扫过 270°
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcSpinnerPainter oldDelegate) => false;
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
