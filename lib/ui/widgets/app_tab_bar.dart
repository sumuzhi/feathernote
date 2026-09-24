/// 底部 TabBar（HTML `.tabbar`）。
///
/// 规格：`left/right 20`、`bottom 12`、`height 64`、圆角 999、
/// 白底 + `0 10px 30px rgba(58,42,32,.10)`；选中项为橙色胶囊 + 白色图标。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tab 定义（图标 / 文案）。
class AppTabSpec {
  /// 构造 Tab。
  const AppTabSpec({required this.label, required this.icon});

  /// 文案。
  final String label;

  /// 图标。
  final IconData icon;
}

/// 三个 Tab：录音 / 历史 / 我的（顺序与 HTML `TABS` 一致）。
const List<AppTabSpec> kAppTabs = <AppTabSpec>[
  AppTabSpec(label: '录音', icon: Icons.mic_rounded),
  AppTabSpec(label: '历史', icon: Icons.history_toggle_off_rounded),
  AppTabSpec(label: '我的', icon: Icons.person_outline_rounded),
];

/// 底部 TabBar。
class AppTabBar extends StatelessWidget {
  /// 构造 TabBar。
  const AppTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  /// 选中下标。
  final int selectedIndex;

  /// 点击回调（回传下标）。
  final ValueChanged<int> onTap;

  /// 含底部安全区的整体占位高度（供页面留白使用）。
  static double reservedHeight(BuildContext context) =>
      AppSpacing.tabBar + AppSpacing.tabBarBottom + MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppSpacing.page,
      right: AppSpacing.page,
      bottom: AppSpacing.tabBarBottom + MediaQuery.viewPaddingOf(context).bottom,
      height: AppSpacing.tabBar,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadow.pill,
        ),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < kAppTabs.length; i++)
              Expanded(
                child: _TabItem(
                  spec: kAppTabs[i],
                  selected: i == selectedIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final AppTabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? Colors.white : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: selected ? AppShadow.orangePill : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(spec.icon, size: 21, color: foreground),
              const SizedBox(height: 3),
              Text(
                spec.label,
                style: AppTextStyles.badge.copyWith(
                  fontSize: 11,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
