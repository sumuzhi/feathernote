/// 状态栏（HTML `.statusbar`）：左时间 + 右侧信号 / WiFi / 电量。
///
/// 图标按 HTML 内联 SVG 的几何用 [CustomPainter] 复刻，避免引入图标字体或位图。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 状态栏。
class StatusBar extends StatelessWidget {
  /// 构造状态栏。
  const StatusBar({super.key, this.time = '9:41'});

  /// 左侧时间文案（默认 9:41，与设计稿一致）。
  final String time;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.statusBar,
      child: Padding(
        padding: const EdgeInsets.only(left: 30, right: 26),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              time,
              style: AppTextStyles.body15.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const CustomPaint(
              size: Size(70, 14),
              painter: _StatusIconPainter(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 信号 / WiFi / 电量图标绘制器（对齐 HTML SVG 的坐标）。
class _StatusIconPainter extends CustomPainter {
  const _StatusIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.fill;

    // 信号强度：三根递增竖条。
    const List<List<double>> bars = <List<double>>[
      <double>[0, 5, 3, 8],
      <double>[5, 3, 3, 10],
      <double>[10, 1, 3, 12],
    ];
    for (final List<double> bar in bars) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar[0], bar[1], bar[2], bar[3]),
          const Radius.circular(1),
        ),
        fill,
      );
    }

    // WiFi：两段同心弧 + 端点圆。
    final Paint arcPaint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(24, 3.5, 13, 10),
      3.9269908169872414, // 225°
      1.5707963267948966, // 90°
      false,
      arcPaint,
    );
    canvas.drawArc(
      const Rect.fromLTWH(26.6, 6.6, 7.8, 6),
      3.9269908169872414,
      1.5707963267948966,
      false,
      arcPaint,
    );
    canvas.drawCircle(const Offset(30.5, 10.5), 1.8, fill);

    // 电量：外框 + 内填充 + 右侧凸点。
    final Paint frame = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(46, 2, 20, 10),
        const Radius.circular(3),
      ),
      frame,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 4, 13, 6),
        const Radius.circular(1.5),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(67.5, 5.5, 1.6, 3),
        const Radius.circular(0.8),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StatusIconPainter oldDelegate) => false;
}
