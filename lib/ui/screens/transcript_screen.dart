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

/// 「展示全部」哨兵值：调用方不传 [TranscriptScreen.visibleCount] 时不做窗口切片
/// （设计稿目录页预览用）。
const int kTranscriptShowAll = 1 << 30;

/// 触底预加载阈值：距列表底部不足该像素时触发 [TranscriptScreen.onLoadMore]。
const double _kLoadMoreTriggerExtent = 800;

/// 转写页。
class TranscriptScreen extends StatefulWidget {
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
    this.visibleCount = kTranscriptShowAll,
    this.onLoadMore,
    this.hitTargetId,
    this.hitNavStamp = 0,
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

  /// 渲染窗口大小（过滤后最多显示的条数）。
  ///
  /// 真分页：页面传入窗口大小，触底时经 [onLoadMore] 扩窗。超长转写（数千段）
  /// 一次性渲染全部 tile 是滚动卡顿的根因（无虚拟化 + 每次 setState 全量布局）。
  final int visibleCount;

  /// 触底扩窗回调（null = 不分页，如设计稿目录页）。
  final VoidCallback? onLoadMore;

  /// 命中定位目标（`segmentId@startMs`）。用户反馈：点上一处/下一处必须滚到
  /// 命中段所在位置。
  final String? hitTargetId;

  /// 命中定位递增戳：变化即触发一次滚动定位（页面在 onPrev/onNext 里 bump）。
  final int hitNavStamp;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  final ScrollController _scrollController = ScrollController();

  /// 已构建条目的定位锚点（`segmentId@startMs` → key），命中定位用。
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  // build 期间记录，供命中定位的「未构建 → 估算跳转」路径使用。
  List<TranscriptItemView> _lastFiltered = const <TranscriptItemView>[];
  int _lastShown = 0;

  @override
  void initState() {
    super.initState();
    // 深链/恢复场景：首帧即带命中目标。
    if (widget.hitTargetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHit());
    }
  }

  @override
  void didUpdateWidget(covariant TranscriptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 页面在「上一处/下一处」时 bump 戳 → 滚动定位到新命中段。
    if (widget.hitNavStamp != oldWidget.hitNavStamp && widget.hitTargetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHit());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(TranscriptItemView item) =>
      _itemKeys.putIfAbsent('${item.segmentId}@${item.startTimeMs}', GlobalKey.new);

  /// 命中定位。
  ///
  /// ① 目标已构建 → [Scrollable.ensureVisible] 精确滚动；
  /// ② 目标未构建（窗口内但视口外）→ 按比例估算偏移先跳转（builder 随即构建
  ///    周边条目），post-frame 再精确对位一次。
  void _scrollToHit() {
    final String? id = widget.hitTargetId;
    if (id == null) return;
    final BuildContext? ctx = _itemKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
      return;
    }
    int pos = -1;
    for (int i = 0; i < _lastShown && i < _lastFiltered.length; i++) {
      final TranscriptItemView it = _lastFiltered[i];
      if ('${it.segmentId}@${it.startTimeMs}' == id) {
        pos = i;
        break;
      }
    }
    if (pos < 0 || !_scrollController.hasClients || _lastShown <= 0) return;
    final double max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo((max * (pos / _lastShown)).clamp(0.0, max));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? c2 = _itemKeys[id]?.currentContext;
      if (c2 != null) {
        Scrollable.ensureVisible(
          c2,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<TranscriptItemView> filtered = widget.selectedFilter == 0
        ? widget.items
        : widget.items
            .where((TranscriptItemView item) => item.ordinal == widget.selectedFilter)
            .toList(growable: false);
    final int shown = widget.visibleCount < filtered.length
        ? widget.visibleCount
        : filtered.length;
    final List<TranscriptItemView> visible = filtered.sublist(0, shown);
    final bool hasMore = filtered.length > shown;
    _lastFiltered = filtered;
    _lastShown = shown;

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
              onTap: widget.onCopyAll,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppPillButton(label: '导出 Markdown', onTap: widget.onExportMarkdown),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 固定 header：顶栏 / 信息条 / 筛选 chips / 命中条不随列表滚动。
          AppTopBar(
            title: '完整转写',
            subtitle: widget.meetingName,
            leadingIcon: Icons.chevron_left_rounded,
            onLeading: widget.onBack,
            actionIcon: Icons.search_rounded,
            onAction: widget.onSearch,
          ),
          _InfoBar(left: widget.infoText, right: widget.charCountText),
          FilterChipRow(
            items: widget.filters,
            onTap: widget.onFilterChanged,
            scrollable: true,
          ),
          // 筛选组与列表之间的呼吸间距（避免 chips 与卡片贴在一起）。
          const SizedBox(height: 16),
          if (widget.hit != null)
            HitBar(
              total: widget.hit!.total,
              current: widget.hit!.current,
              keyword: widget.hit!.keyword,
              onPrev: widget.hit!.onPrev,
              onNext: widget.hit!.onNext,
              onClose: widget.hit!.onClose,
            ),
          // 仅转写列表滚动（底部留白避开 CTA：手势条 inset + CTA 高度 + 余量）。
          // ListView.builder 虚拟化：只构建/布局可见条目——超长转写（数千段）
          // 用 SingleChildScrollView+Column 会全量布局，是滚动卡顿的根因。
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                // 触底预加载：距底部不足阈值即扩窗（hasMore 时）。
                if (widget.onLoadMore == null ||
                    !hasMore ||
                    notification.metrics.extentAfter >= _kLoadMoreTriggerExtent) {
                  return false;
                }
                widget.onLoadMore!();
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  22,
                  8,
                  22,
                  MediaQuery.viewPaddingOf(context).bottom + 100,
                ),
                itemCount: visible.isEmpty
                    ? 1
                    : visible.length + (widget.segmentLoadingText != null ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        '该说话人暂无转写内容',
                        style: AppTextStyles.meta,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  // 末尾：加载进度胶囊（窗口未满时才出现，全部加载完即消失）。
                  if (index >= visible.length) {
                    return AppSegmentedLoadingPill(text: widget.segmentLoadingText!);
                  }
                  return TranscriptTile(
                    // GlobalKey：命中定位锚点（segmentId+起点唯一定位）。
                    // 不用 index：列表重排/过滤后 index 会变，会让 Flutter 按位置
                    // 错误复用元素，进度组件就可能渲染到别的条目上。
                    key: _keyFor(visible[index]),
                    item: visible[index],
                    onExpand: widget.onExpandSegment == null
                        ? null
                        : () => widget.onExpandSegment!(index),
                    onPlay: widget.onPlaySegment == null
                        ? null
                        : () => widget.onPlaySegment!(visible[index]),
                  );
                },
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
