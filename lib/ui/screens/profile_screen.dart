/// 屏 05：设置（HTML `#s05`；App 无登录，原用户卡已移除，统计模块保留）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_switch.dart';
import '../widgets/app_tab_bar.dart';
import '../widgets/surface_card.dart';
import 'screen_frame.dart';

/// 统计项。
class ProfileStatView {
  /// 构造统计项。
  const ProfileStatView({required this.value, required this.label});

  /// 数值（如「128」/「64h」）。
  final String value;

  /// 说明。
  final String label;
}

/// 设置行。
class ProfileSettingView {
  /// 构造设置行。
  const ProfileSettingView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.toggle = false,
    this.toggleValue = false,
    this.onTap,
    this.onToggle,
    this.switchLabel,
  });

  /// 左侧图标。
  final IconData icon;

  /// 标题。
  final String title;

  /// 副标题。
  final String subtitle;

  /// 右侧值（有值时显示值 + 右箭头，可点击）。
  final String? value;

  /// 是否为开关行。
  final bool toggle;

  /// 开关当前值。
  final bool toggleValue;

  /// 点击整行（值行）。
  final VoidCallback? onTap;

  /// 切换开关。
  final ValueChanged<bool>? onToggle;

  /// 开关无障碍标签。
  final String? switchLabel;
}

/// 设置分组。
class ProfileSectionView {
  /// 构造分组。
  const ProfileSectionView({required this.title, required this.rows});

  /// 分组标题。
  final String title;

  /// 设置行。
  final List<ProfileSettingView> rows;
}

/// 设置页（原「我的」屏 05：App 无登录，用户卡已移除，**统计模块保留**）。
class ProfileScreen extends StatelessWidget {
  /// 构造设置页。
  const ProfileScreen({
    super.key,
    required this.stats,
    required this.sections,
    required this.onSettings,
    required this.onTabTap,
    this.selectedTab = 2,
  });

  /// 设置分组。
  final List<ProfileSectionView> sections;

  /// 点击右上设置。
  final VoidCallback onSettings;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 选中 Tab（默认 2 = 设置）。
  final int selectedTab;

  /// 统计项（3 个：场会议 / 累计时长 / 场已总结）。
  final List<ProfileStatView> stats;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      // 只滚动配置项列表：「设置」标题行固定在顶部。
      scrollable: false,
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            // 用户要求：移除右上角「关于」icon，仅保留标题。
            child: Text('设置', style: AppTextStyles.sectionTitle),
          ),
          Expanded(
            child: SingleChildScrollView(
              // 底部留白 = TabBar 全保留高度 + 20 余量：
              // 修复版本行 / 最后一条设置项被底栏遮住。
              padding: EdgeInsets.only(bottom: AppTabBar.reservedHeight(context) + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 统计模块（保留）：场会议 / 累计时长 / 场已总结。
                  // 跟随设置项一起滚动。
                  SurfaceCard(
                    margin: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < stats.length; i++)
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                Text(stats[i].value, style: AppTextStyles.statValue),
                                const SizedBox(height: 5),
                                Text(stats[i].label, style: AppTextStyles.metaSmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final ProfileSectionView section in sections) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 9),
                      child: Text(section.title, style: AppTextStyles.meta),
                    ),
                    SurfaceCard(
                      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < section.rows.length; i++)
                            _SettingRow(
                              row: section.rows[i],
                              showDivider: i != section.rows.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                  // 用户要求：移除页脚「版本 x.y.z · 端化运行 · 构建戳」——
                  // 版本信息只在「运行参数 → 版本」行展示（那里同时承担更新检查入口）。
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.row, required this.showDivider});

  final ProfileSettingView row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.line, width: 1))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        // 溢出修复：右侧「值」文本必须有宽度上限，否则长模型名 / 降级原因会把
        // 整行撑爆（真机右缘黄黑条纹）。预算 = 行宽 - 图标区(34+13)，值最多占一半，
        // 剩余全给中间标题/副标题列（Expanded），超长用省略号。
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double budget =
                (constraints.maxWidth - 47).clamp(0.0, double.infinity);
            final double maxValueWidth = budget * 0.5;

            final Widget trailing;
            if (row.toggle) {
              trailing = AppSwitch(
                value: row.toggleValue,
                onChanged: row.onToggle ?? (_) {},
                semanticLabel: row.switchLabel ?? row.title,
              );
            } else {
              trailing = GestureDetector(
                onTap: row.onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxValueWidth),
                      child: Text(
                        row.value ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTextStyles.input.copyWith(color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: AppColors.faint,
                    ),
                  ],
                ),
              );
            }

            return GestureDetector(
              // 整行可点：选择类点行即编辑/查看（原仅右侧 value 可点）。
              // 开关行不接管——开关自身响应，避免双触发。
              onTap: row.toggle ? null : row.onTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.orangeSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(row.icon, size: 17, color: AppColors.orange),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(row.title, style: AppTextStyles.settingTitle),
                        // 选择类条目（右侧有值）：不显示副标题，保持单行，
                        // 信息由「标题 + 右值」承载，避免占两行。
                        if (row.value == null || row.value!.isEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(row.subtitle, style: AppTextStyles.metaSmall),
                        ],
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
