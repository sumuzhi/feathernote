/// 启动页（**静态**，无动画 —— 2026-09-26 用户要求关闭开屏动画、加快进入）。
///
/// 进入策略：**后端装配完成即进首页**，不再固定停留 2.4s：
/// - 最短停留 [_kMinDisplay]：避免首帧刚画完就切页的闪跳观感；
/// - 兜底上限 [_kMaxWait]：后端装配再慢也不把用户挡在启动页
///   （首页自带加载态，历史流 / 一句话已在路上）。
/// 后端装配（配置校验 / DB 打开 / 引擎构建）、历史列表流与「一句话」预取
/// 均在启动页期间并行完成，主页首帧即有数据（沿用原预热设计）。
///
/// 视觉：静态终帧 = 图标 100×100 圆角 24 + 「声羽」/ FEATHERNOTE / slogan。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log/log.dart';
import '../providers/app_providers.dart';
import '../providers/quote_provider.dart';
import '../theme/app_theme.dart';

/// 启动页最短停留时长（防首帧闪跳的最小观感保护）。
const Duration _kMinDisplay = Duration(milliseconds: 400);

/// 启动页最长等待（后端装配超限时放行进首页，不阻塞用户）。
const Duration _kMaxWait = Duration(milliseconds: 2000);

/// 启动页。
class SplashScreen extends ConsumerStatefulWidget {
  /// 构造启动页。
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // 预热后端装配（配置校验 / DB 打开 / 引擎构建）与历史列表流：
    // 主页首帧即有数据，不再有「进首页后卡一下」。
    final Future<void> backendReady = ref.watch(backendProvider.future).then(
      (_) => logInfo('splash', '后端预热完成（装配 + DB 就绪）'),
      onError: (Object e) => logWarn('splash', '后端预热失败：$e'),
    );
    ref.watch(meetingsProvider);
    // 预取「一句话」：进入首页前请求已在路上（超时 3s），进首页即可见。
    ref.watch(dailyQuoteProvider);

    // 就绪即进首页：min(最短停留, 后端就绪) 与 兜底上限 取先到。
    unawaited(
      Future.wait<void>(<Future<void>>[
        Future<void>.delayed(_kMinDisplay),
        backendReady.timeout(
          _kMaxWait,
          onTimeout: () => logWarn('splash', '后端预热超过 $_kMaxWait，放行进首页'),
        ),
      ]).then((_) => _goHome()),
    );
  }

  void _goHome() {
    if (!mounted || _navigated) return;
    _navigated = true;
    // go 而非 push：启动页不留返回栈（系统返回在首页即为「双击退出」）。
    context.go('/');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 提前解码启动图标：避免首帧绘制时同步触发 460KB PNG 解码造成掉帧。
    precacheImage(const AssetImage('assets/brand/icon-combined-1024.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _BrandIcon(),
            const SizedBox(height: 34),
            // 「声羽」：42px / w600 / 字距 10。
            Text(
              '声 羽',
              style: AppTextStyles.pageTitle.copyWith(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                letterSpacing: 10,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'FEATHERNOTE',
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
}

/// 品牌图标：100×100 圆角 24 + 橙色投影（原动画终帧的静态版本）。
class _BrandIcon extends StatelessWidget {
  const _BrandIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x52F0783C), // rgba(240,120,60,.32)
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
    );
  }
}
