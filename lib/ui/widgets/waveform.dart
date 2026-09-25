/// 录音波形（HTML `.wave`）：44 根橙色柱，中间高两侧低。
///
/// 柱高 / 透明度 / 动画时长**完全照抄** HTML 的 `buildWave()`：
/// ```js
/// const n = 44, mid = 22;
/// dist = Math.abs(i-mid)/mid
/// h = 14 + sin(i*0.55)*10 + (1-dist)*46*(0.6+0.4*sin(i*1.3))
/// h = clamp(8, 78)
/// opacity = 0.25 + (1-dist)*0.75
/// delay = i*0.045s ; duration = 0.9 + (i%5)*0.12s
/// ```
/// 动画为 `scaleY 1 → .45 → 1`；命中「减少动效」时降级为静态柱。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 波形柱数量（HTML `n = 44`）。
const int kWaveformBarCount = 44;

/// 单根柱的静态高度（与 HTML `buildWave` 一致）。
double waveformBarHeight(int index) {
  const int mid = 22;
  final double dist = (index - mid).abs() / mid;
  final double h = 14 +
      math.sin(index * 0.55) * 10 +
      (1 - dist) * 46 * (0.6 + 0.4 * math.sin(index * 1.3));
  return h.clamp(8.0, 78.0);
}

/// 单根柱的静态透明度（与 HTML `buildWave` 一致）。
double waveformBarOpacity(int index) {
  const int mid = 22;
  final double dist = (index - mid).abs() / mid;
  return 0.25 + (1 - dist) * 0.75;
}

/// 单根柱的动画周期（秒）。
double _barDuration(int index) => 0.9 + (index % 5) * 0.12;

/// 单根柱的动画延迟（秒）。
double _barDelay(int index) => index * 0.045;

/// 录音波形。
class Waveform extends StatefulWidget {
  /// 构造波形。
  const Waveform({super.key, this.height = 88, this.animating = true});

  /// 容器高度（HTML `.wave` 为 88）。
  final double height;

  /// 是否正在推进动画。暂停 / 收尾时应传 `false`：
  /// 柱体**冻结在当前电平**并停止推进，不出现「假装在动」的空转动画。
  final bool animating;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform> with TickerProviderStateMixin {
  final List<AnimationController> _controllers = <AnimationController>[];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < kWaveformBarCount; i++) {
      final double period = _barDuration(i);
      final AnimationController controller = AnimationController(
        vsync: this,
        // `repeat(reverse: true)` 走完一个来回 = 两个 duration，故折半对齐 HTML 周期。
        duration: Duration(milliseconds: (period * 500).round()),
      );
      final double delay = _barDelay(i);
      controller.value = (delay / period) % 1.0;
      _controllers.add(controller);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animating != widget.animating) {
      _sync();
    }
  }

  /// 按「减少动效」与 [Waveform.animating] 决定每个控制器的运行状态。
  ///
  /// - 减少动效 → 停并归位静态（scale=1）；
  /// - 暂停（`animating == false`）→ 停但**保留当前值**（冻结在当前电平）；
  /// - 否则 → 循环动画。
  void _sync() {
    for (final AnimationController controller in _controllers) {
      if (_reduceMotion) {
        if (controller.isAnimating) controller.stop();
        controller.value = 0;
      } else if (!widget.animating) {
        if (controller.isAnimating) controller.stop();
      } else if (!controller.isAnimating) {
        controller.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    for (final AnimationController controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      // 44 根柱固定占 352px：窄屏（<360dp）会被 Row 横向溢出，在页面右缘
      // 出现黄黑条纹（真机 bug）。FittedBox 整体等比缩小，宽屏不受影响。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedBuilder(
          animation: Listenable.merge(_controllers),
          builder: (BuildContext context, Widget? child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < kWaveformBarCount; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _WaveBar(
                      height: waveformBarHeight(i),
                      opacity: waveformBarOpacity(i),
                      scale:
                          _reduceMotion ? 1.0 : 1.0 - 0.55 * _controllers[i].value,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WaveBar extends StatelessWidget {
  const _WaveBar({
    required this.height,
    required this.opacity,
    required this.scale,
  });

  final double height;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Align(
        alignment: Alignment.center,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(1, scale, 1),
          child: Container(
            width: 4,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
