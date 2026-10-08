/// 屏 14：导入音视频 · 选择文件 + 最近导入（HTML 设计稿屏 14）。
///
/// 视觉层只做渲染：数据与交互全部由 `lib/ui/pages/import_page.dart` 翻译。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/history_card.dart';
import '../widgets/section_header.dart';
import '../widgets/surface_card.dart';
import 'screen_frame.dart';

/// 屏 14 视觉。
class ImportIdleScreen extends StatelessWidget {
  /// 构造屏 14。
  const ImportIdleScreen({
    super.key,
    required this.onPickFile,
    required this.recentItems,
    required this.onTabTap,
    this.selectedTab = 0,
    this.picking = false,
  });

  /// 点击「选择文件」。
  final VoidCallback onPickFile;

  /// 最近导入（最多 5 条）。
  final List<HistoryItemView> recentItems;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 选中 Tab。
  final int selectedTab;

  /// 是否在选择文件中（按钮禁用）。
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final bool hasRecent = recentItems.isNotEmpty;
    return ScreenFrame(
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      bottomSpacer: hasRecent ? AppSpacing.tabBarSpacer : 120,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: _PageTitle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 0),
            child: _PickCard(onPickFile: onPickFile, picking: picking),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 0),
            child: Text(
              '单个文件 ≤ 2GB · 时长 ≤ 12 小时 · 原文件不会被修改',
              style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
            ),
          ),
          if (hasRecent) ...<Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.page, 26, AppSpacing.page, 0),
              child: SectionHeader(title: '最近导入'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
              child: Column(
                children: <Widget>[
                  for (final HistoryItemView item in recentItems)
                    HistoryCard(item: item),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 页标题（const 节点里引用，抽出来保证标题样式可 const 化）。
class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) =>
      Text('导入音视频', style: AppTextStyles.pageTitle);
}

/// 「选择文件」大卡（HTML 设计稿屏 14 主卡）。
class _PickCard extends StatelessWidget {
  const _PickCard({required this.onPickFile, required this.picking});

  final VoidCallback onPickFile;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '选择音视频文件',
      child: GestureDetector(
        onTap: picking ? null : onPickFile,
        behavior: HitTestBehavior.opaque,
        child: SurfaceCard(
          radius: AppRadius.card,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: Column(
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1E6),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.upload_file_rounded,
                  size: 30,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                picking ? '正在打开文件选择器…' : '选择视频 / 音频文件',
                style: AppTextStyles.settingTitle.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                '上传视频或音频，自动分离音轨并生成纪要',
                style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
