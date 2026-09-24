/// 录音波形：一排竖向圆角柱（橙色深浅），随音量起伏。
///
/// - 不使用任何动画库；`AnimatedContainer` 做柱高过渡即可；
/// - **尊重 reduced-motion**：系统关闭动画时只做静态渲染，不持续重绘；
/// - 数据来源：`waveformProvider`（录音期间由 PCM 计算 RMS 后按 ~15Hz 推入）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 波形条。
class Waveform extends StatelessWidget {
  /// 构造波形。
  const Waveform({
    super.key,
    required this.levels,
    this.barCount = 44,
    this.height = 68,
    this.barWidth = 3,
    this.gap = 4,
    this.color = AppColors.primary,
    this.active = true,
  });

  /// 音量序列（0–1，最新的在末尾）；不足 [barCount] 时左侧补零。
  final List<double> levels;

  /// 柱子数量。
  final int barCount;

  /// 组件高度（最高柱高）。
  final double height;

  /// 柱宽。
  final double barWidth;

  /// 柱间距。
  final double gap;

  /// 柱色。
  final Color color;

  /// 是否处于活动（录音中）状态。
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final List<double> bars = _tail(levels, barCount);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (int i = 0; i < bars.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: _Bar(
                level: active ? bars[i] : 0,
                height: height,
                width: barWidth,
                color: color,
                // 中间深、两端浅，模拟设计稿的「橙色深浅」。
                opacity: _edgeFade(i, bars.length),
                animate: !reduceMotion,
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.level,
    required this.height,
    required this.width,
    required this.color,
    required this.opacity,
    required this.animate,
  });

  final double level;
  final double height;
  final double width;
  final Color color;
  final double opacity;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    const double minHeight = 6;
    final double target = minHeight + level.clamp(0.0, 1.0) * (height - minHeight);
    final Widget bar = Container(
      width: width,
      height: target,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
    if (!animate) return bar;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: width,
      height: target,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}

double _edgeFade(int index, int total) {
  if (total <= 1) return 0.85;
  final double distanceFromCenter = (index - (total - 1) / 2).abs() / ((total - 1) / 2);
  return 0.95 - 0.5 * distanceFromCenter;
}

List<double> _tail(List<double> source, int count) {
  if (source.length >= count) {
    return source.sublist(source.length - count);
  }
  final List<double> padded = List<double>.filled(count - source.length, 0);
  return <double>[...padded, ...source];
}
