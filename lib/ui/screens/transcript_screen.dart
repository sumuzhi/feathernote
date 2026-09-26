/// 屏 07 / 12：完整转写（HTML `#s07` / `#s12`）。
///
/// 屏 12 额外包含：命中条（「找到 12 处「激活」」+ `3 / 12` + 上下切换 + 关闭）、
/// 命中片段浅橙高亮 + 「展开这段」、底部「分段加载中」胶囊。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/filter_chips.dart';
import '../widgets/hit_bar.dart';
import '../widgets/progress_pill.dart';
import '../widgets/transcript_tile.dart';
import 'screen_frame.dart';

/// 转写页。
class TranscriptScreen extends StatelessWidget {
  /// 构造转写页。
  const TranscriptScreen({
    super.key,
    required this.meetingName,
    required this.infoText,
    required this.charCountText,
    required this.filters,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.items,
    required this.onBack,
    required this.onSearch,
    required this.onCopyAll,
    required this.onExportMarkdown,
    this.hit,
    this.segmentLoadingText,
    this.onExpandSegment,
    this.onPlaySegment,
  });

  /// 顶栏副标题（会议名）。
  final String meetingName;

  /// 信息条左侧（「32 分钟 · 3 位说话人」）。
  final String infoText;

  /// 信息条右侧（「1,860 字」）。
  final String charCountText;

  /// 说话人过滤 chip。
  final List<FilterChipView> filters;

  /// 选中的过滤项。
  final int selectedFilter;

  /// 切换过滤项。
  final ValueChanged<int> onFilterChanged;

  /// 转写条目。
  final List<TranscriptItemView> items;

  /// 返回。
  final VoidCallback onBack;

  /// 搜索。
  final VoidCallback onSearch;

  /// 复制全文。
  final VoidCallback onCopyAll;

  /// 导出 Markdown。
  final VoidCallback onExportMarkdown;

  /// 命中条（屏 12 才有）。
  final TranscriptHitView? hit;

  /// 「分段加载中」文案（屏 12）。
  final String? segmentLoadingText;

  /// 点击「展开这段」（回传条目下标）。
  final ValueChanged<int>? onExpandSegment;

  /// 点击 segment 的播放按钮（回传条目数据）。
  ///
  /// ⚠️ 必须回传**条目**而不是过滤后列表的下标：页面按过滤下标去索引全量
  /// `_segments` 会错位，导致「过滤说话人后点播放播的是别的话」。
  final ValueChanged<TranscriptItemView>? onPlaySegment;

  @override
  Widget build(BuildContext context) {
    final List<TranscriptItemView> visible = selectedFilter == 0
        ? items
        : items
            .where((TranscriptItemView item) => item.ordinal == selectedFilter)
            .toList(growable: false);

    return ScreenFrame(
      // 只滚动转写列表：顶栏 / 信息条 / 筛选 / 命中条固定（自行管理滚动）。
      scrollable: false,
      bottomSpacer: 0,
      bottomCta: Row(
        children: <Widget>[
          Expanded(
            child: AppGhostPillButton(
              label: '复制全文',
              icon: Icons.copy_all_rounded,
              onTap: onCopyAll,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: AppPillButton(label: '导出 Markdown', onTap: onExportMarkdown)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 固定 header：顶栏 / 信息条 / 筛选 chips / 命中条不随列表滚动。
          AppTopBar(
            title: '完整转写',
            subtitle: meetingName,
            leadingIcon: Icons.chevron_left_rounded,
            onLeading: onBack,
            actionIcon: Icons.search_rounded,
            onAction: onSearch,
          ),
          _InfoBar(left: infoText, right: charCountText),
          FilterChipRow(
            items: filters,
            onTap: onFilterChanged,
            scrollable: true,
          ),
          // 筛选组与列表之间的呼吸间距（避免 chips 与卡片贴在一起）。
          const SizedBox(height: 10),
          if (hit != null)
            HitBar(
              total: hit!.total,
              current: hit!.current,
              keyword: hit!.keyword,
              onPrev: hit!.onPrev,
              onNext: hit!.onNext,
              onClose: hit!.onClose,
            ),
          // 仅转写列表滚动（底部留白避开 CTA：手势条 inset + CTA 高度 + 余量）。
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                22,
                8,
                22,
                MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        '该说话人暂无转写内容',
                        style: AppTextStyles.meta,
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (int i = 0; i < visible.length; i++)
                      TranscriptTile(
                        // 稳定 key：段由「segmentId + 起点」唯一定位。
                        // 不用 index：列表重排/过滤后 index 会变，会让 Flutter 按位置
                        // 错误复用元素，进度组件就可能渲染到别的条目上。
                        key: ValueKey<String>(
                          '${visible[i].segmentId}@${visible[i].startTimeMs}',
                        ),
                        item: visible[i],
                        onExpand:
                            onExpandSegment == null ? null : () => onExpandSegment!(i),
                        onPlay:
                            onPlaySegment == null ? null : () => onPlaySegment!(visible[i]),
                      ),
                  if (segmentLoadingText != null)
                    AppSegmentedLoadingPill(text: segmentLoadingText!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 命中条数据（屏 12）。
class TranscriptHitView {
  /// 构造命中数据。
  const TranscriptHitView({
    required this.total,
    required this.current,
    required this.keyword,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  /// 命中总数。
  final int total;

  /// 当前序号。
  final int current;

  /// 关键词。
  final String keyword;

  /// 上一处。
  final VoidCallback onPrev;

  /// 下一处。
  final VoidCallback onNext;

  /// 关闭。
  final VoidCallback onClose;
}

/// 信息条（HTML `.tr-info`）：高 48，圆角 999。
class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
      height: AppSpacing.infoBar,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              left,
              style: AppTextStyles.input.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(right, style: AppTextStyles.meta),
        ],
      ),
    );
  }
}
