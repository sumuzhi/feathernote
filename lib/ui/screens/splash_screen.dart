/// 启动动画页（brand-assets/preview/splash.html 的 Flutter 复刻）。
///
/// 时序（约 2.4s 后自动进首页）：
/// 1. 图标 100×100 圆角 24：scale .82→1 + 淡入（.5s，easeOutCubic）；
/// 2. 四圈录音波纹（呼应产品核心动作）：1.5s 内由内向外扩散淡出，逐圈延迟 .22s；
/// 3. 「声记」（字距 10）→ "SONICMEMO"（字距 5）→ slogan「听见每一场会议的重点」。
///
/// 性能要点：
/// - AnimatedBuilder **只包波纹 + 图标**，文案区静态不随动画逐帧重建；
/// - `didChangeDependencies` 里 precacheImage 预热图标解码，避免首帧掉帧；
/// - debug 构建（JIT + 无 shader 缓存）动画天然比 release 卡，真机以 release 验收。
///
/// 路由：`/splash` 为 initialLocation，动画结束后 `go('/')`（不留返回栈）。
/// **时长控制**：[kSplashDuration]（本文件顶部常量），改一处即调总时长。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// 启动动画停留时长（波纹播完一轮 + 文案入场的冗余）。
const Duration kSplashDuration = Duration(milliseconds: 2400);

/// 启动动画页。
class SplashScreen extends StatefulWidget {
  /// 构造启动页。
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // 单控制器驱动：波纹循环（1.5s）+ 图标入场（前 .5s 共用时间轴）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final Animation<double> _iconIn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.34, curve: Curves.easeOutCubic),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward(from: 0);
    _timer = Timer(kSplashDuration, () {
      if (!mounted) return;
      // go 而非 push：启动页不留返回栈（系统返回在首页即为「双击退出」）。
      context.go('/');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 提前解码启动图标：避免首帧绘制时同步触发 460KB PNG 解码造成掉帧。
    precacheImage(const AssetImage('assets/brand/icon-combined-1024.png'), context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 波纹全部播完（末圈 0.66 + 1.0 ≈ 1.66s）后不再逐帧 rebuild：
    // 用静态展示替代，避免控制器空转期间的无效重绘（「最后一刻卡顿」来源之一）。
    final bool animating = _controller.isAnimating || _controller.value < 1.0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        // ⚠️ AnimatedBuilder 只包「动的东西」（波纹 + 图标）；
        // 文案区保持静态，不随动画每帧重建（修复启动页卡顿）。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 190,
              height: 190,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? _) {
                  final double t = _controller.value;
                  return SizedBox(
                    width: 190,
                    height: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior:
                          Clip.none, // 波纹可溢出光晕区（对齐 HTML 动效）
                      children: <Widget>[
                        // 四圈录音波纹：逐圈延迟 .22s 扩散淡出。
                        for (int i = 0; i < 4; i++)
                          _RippleRing(
                            progress: _rippleProgress(t, i * 0.22),
                          ),
                        // 图标：100×100 圆角 24，缩放入场 + 阴影。
                        Transform.scale(
                          scale: 0.82 + 0.18 * _iconIn.value,
                          child: Opacity(
                            opacity: _iconIn.value,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color:
                                        Color(0x52F0783C), // rgba(240,120,60,.32)
                                    offset: Offset(0, 14),
                                    blurRadius: 34,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/brand/icon-combined-1024.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                // 动画结束（波纹收尾完成）后展示静态终帧。
                child: animating ? null : _buildStaticHero(),
              ),
            ),
            const SizedBox(height: 34),
            // 「声记」：42px / w600 / 字距 10。
            Text(
              '声 记',
              style: AppTextStyles.pageTitle.copyWith(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'SONICMEMO',
              style: AppTextStyles.meta.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 26),
            Text(
              '听见每一场会议的重点',
              style: AppTextStyles.metaSmall.copyWith(
                fontSize: 13.5,
                letterSpacing: 2,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 动画结束后的静态终帧（图标满幅，无波纹）。
  Widget _buildStaticHero() {
    return SizedBox(
      width: 190,
      height: 190,
      child: Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x52F0783C),
                offset: Offset(0, 14),
                blurRadius: 34,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/brand/icon-combined-1024.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  /// 第 [ring] 圈在控制器进度 [t]（0–1）下的波纹进度；未开始返回 0。
  ///
  /// 每圈延迟 ring×0.22s（折算到 0–1 进度即 start），local <0 视为未开始。
  static double _rippleProgress(double t, double offsetSeconds) {
    const double period = 1.0; // 控制器 1.5s = 1 圈波纹周期
    final double start = offsetSeconds / 1.5; // .22s 延迟折算到 0–1 进度
    final double local = t - start;
    if (local <= 0) return 0;
    return local % period == 0 ? period : local;
  }
}

/// 单圈波纹：2px 橙色圆环，scale .55→2.35，透明度 .42→0；周期外不渲染。
///
/// 性能关键：圆环**绘制内容完全静态**（固定 alpha 的 border），淡出与缩放
/// 全部交给 [Opacity] / [Transform] 在合成层完成——不逐帧重绘 border，
/// 也不会因 alpha 连续变化反复触发新 shader 编译（「最后一刻卡顿」根因）。
class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0 || clamped >= 1) return const SizedBox.shrink();
    final double alpha = 0.42 * (1 - clamped);
    final double scale = 0.55 + 1.8 * clamped;
    return IgnorePointer(
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: alpha,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.orange, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
