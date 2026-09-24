/// 底部 TabBar 外壳：三 pill（录音 / 历史 / 我的），选中态为橙色 pill。
///
/// 设计稿 TabBar（2:14）：左右 21、上 12、下含安全区，Pill 高 62，圆角 36，
/// 白色底 + 暖棕阴影（alpha 0.18 / y=6 / blur 18 / spread −2）。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Tab 定义。
class _TabSpec {
  const _TabSpec({required this.path, required this.label, required this.icon});

  final String path;
  final String label;
  final IconData icon;
}

const List<_TabSpec> _tabs = <_TabSpec>[
  _TabSpec(path: '/', label: '录音', icon: Icons.mic_rounded),
  _TabSpec(path: '/history', label: '历史', icon: Icons.history_rounded),
  _TabSpec(path: '/profile', label: '我的', icon: Icons.person_outline_rounded),
];

/// 应用外壳。
class AppShell extends StatelessWidget {
  /// 构造外壳。
  const AppShell({super.key, required this.location, required this.child});

  /// 当前路由地址（用于推导选中项）。
  final String location;

  /// 当前页面。
  final Widget child;

  int get _selectedIndex {
    for (int i = 0; i < _tabs.length; i++) {
      final String path = _tabs[i].path;
      if (path != '/' && location.startsWith(path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: child,
      bottomNavigationBar: _AppTabBar(selectedIndex: _selectedIndex),
    );
  }
}

class _AppTabBar extends StatelessWidget {
  const _AppTabBar({required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21),
          child: Container(
            height: 62,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadow.pill,
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _TabItem(
                      spec: _tabs[i],
                      selected: i == selectedIndex,
                      onTap: () => context.go(_tabs[i].path),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.spec, required this.selected, required this.onTap});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? Colors.white : AppColors.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill - 6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(spec.icon, size: 20, color: foreground),
              const SizedBox(height: 2),
              Text(
                spec.label,
                style: AppTextStyles.metaSmall.copyWith(
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
