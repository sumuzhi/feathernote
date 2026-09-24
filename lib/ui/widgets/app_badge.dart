/// 徽标与标签（HTML `.badge` / `.tag` / `.auto`）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 徽标语义。
enum AppBadgeTone {
  /// 已总结（浅橙底 + 橙字）。
  summarized,

  /// 已完成（浅绿底 + 绿字）。
  done,

  /// 中性（灰底 + 灰字）。
  neutral,
}

/// 胶囊徽标（HTML `.badge`）。
class AppBadge extends StatelessWidget {
  /// 构造徽标。
  const AppBadge({super.key, required this.text, this.tone = AppBadgeTone.summarized});

  /// 文案。
  final String text;

  /// 语义色。
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (tone) {
      case AppBadgeTone.summarized:
        background = AppColors.orangeSoft;
        foreground = AppColors.orange;
      case AppBadgeTone.done:
        background = AppColors.greenBg;
        foreground = AppColors.green;
      case AppBadgeTone.neutral:
        background = AppColors.grayWash;
        foreground = AppColors.faint;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.badge.copyWith(color: foreground),
      ),
    );
  }
}

/// 卡片头部的次级标签（HTML `.sum-card .hd .tag`）。
class AppTag extends StatelessWidget {
  /// 构造标签。
  const AppTag({super.key, required this.text, this.wash = false});

  /// 文案。
  final String text;

  /// 是否使用 chip 底色（s11 的「内容较长」标签用 `--orange-wash`）。
  final bool wash;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: wash ? AppColors.orangeWash : AppColors.orangeSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.badge.copyWith(color: AppColors.orange),
      ),
    );
  }
}

/// 实时转写卡右上角的「自动滚动 / 转写已暂停」标签（HTML `.live-card .hd .auto`）。
class AppLiveTag extends StatelessWidget {
  /// 构造标签。
  const AppLiveTag({super.key, required this.text, this.paused = false});

  /// 文案。
  final String text;

  /// 暂停态（灰底灰字）。
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: paused ? AppColors.grayWash : AppColors.orangeSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.badge.copyWith(
          color: paused ? AppColors.faint : AppColors.orange,
        ),
      ),
    );
  }
}
