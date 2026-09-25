/// 屏 02 / 06 / 13：录音中（HTML `#s02` / `#s06` / `#s13`）。
///
/// 三个屏共用同一份布局，差异全部由数据驱动：
/// - 屏 06：顶部断线 Toast（[topOverlay]）+ 标题半透明 + 「转写已暂停」+ 末条「待上传」；
/// - 屏 13：8 个说话人 chip（第 8 个灰态）+ 右下「回到底部」FAB + 副标题「已识别 8 人」。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/recording_controls.dart' as controls;
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_tile.dart';
import '../widgets/waveform.dart';
import 'screen_frame.dart';

/// 录音页。
class RecordingScreen extends StatelessWidget {
  /// 构造录音页。
  const RecordingScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.clock,
    required this.speakers,
    required this.items,
    required this.liveTag,
    required this.paused,
    required this.onClose,
    required this.onSettings,
    required this.onPauseToggle,
    required this.onStop,
    required this.onBookmark,
    required this.onTabTap,
    this.dimTitle = false,
    this.liveTagPaused = false,
    this.showBackToBottom = false,
    this.onBackToBottom,
    this.topOverlay,
    this.selectedTab = 0,
    this.scrollController,
    this.stopping = false,
  });

  /// 顶栏标题（「录音中」）。
  final String title;

  /// 顶栏副标题（「会议模式」/「会议模式 · 已识别 8 人」）。
  final String subtitle;

  /// 计时器文案（如「12:34」）。
  final String clock;

  /// 说话人 chip。
  final List<SpeakerChipView> speakers;

  /// 实时转写条目。
  final List<TranscriptItemView> items;

  /// 实时转写卡右上角标签（「自动滚动」/「转写已暂停」）。
  final String liveTag;

  /// 是否已暂停（决定暂停键图标）。
  final bool paused;

  /// 关闭。
  final VoidCallback onClose;

  /// 设置。
  final VoidCallback onSettings;

  /// 暂停 / 继续。
  final VoidCallback onPauseToggle;

  /// 结束并生成。
  final VoidCallback onStop;

  /// 打标记。
  final VoidCallback onBookmark;

  /// 底部 Tab 点击。
  final ValueChanged<int> onTabTap;

  /// 标题是否半透明（屏 06）。
  final bool dimTitle;

  /// 标签是否灰态（屏 06 的「转写已暂停」）。
  final bool liveTagPaused;

  /// 是否展示「回到底部」FAB（屏 13）。
  final bool showBackToBottom;

  /// 点击 FAB。
  final VoidCallback? onBackToBottom;

  /// 顶部浮层（断线 Toast）。
  final Widget? topOverlay;

  /// 选中 Tab。
  final int selectedTab;

  /// 转写列表滚动控制器（自动滚到底用）。
  final ScrollController? scrollController;

  /// 是否正在收尾（「结束并生成」就地 loading，三键禁用）。
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      scrollable: false,
      bottomSpacer: 0,
      tabIndex: selectedTab,
      onTabTap: onTabTap,
      topOverlay: topOverlay,
      floating: showBackToBottom
          ? Semantics(
              button: true,
              label: '回到底部',
              child: GestureDetector(
                onTap: onBackToBottom,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    boxShadow: AppShadow.fab,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_downward_rounded,
                    size: 17,
                    color: AppColors.orange,
                  ),
                ),
              ),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTopBar(
            title: title,
            subtitle: subtitle,
            dimTitle: dimTitle,
            leadingIcon: Icons.close_rounded,
            onLeading: onClose,
            actionIcon: Icons.settings_outlined,
            onAction: onSettings,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 0),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                // 计时越长字号越大位：超长（跨小时）时整体缩小，不横向溢出。
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(clock, style: AppTextStyles.clock),
                  ),
                ),
              ],
            ),
          ),
          // 暂停 / 收尾时冻结波形（不再「假装在动」），恢复后继续。
          Waveform(animating: !paused && !stopping),
          SpeakerChipRow(items: speakers),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(AppSpacing.page, 18, AppSpacing.page, 0),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: AppShadow.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text('实时转写', style: AppTextStyles.cardHead),
                      AppLiveTag(text: liveTag, paused: liveTagPaused),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _LiveList(
                      items: items,
                      scrollController: scrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
          controls.RecordingControls(
            paused: paused,
            stopping: stopping,
            onPauseToggle: onPauseToggle,
            onStop: onStop,
            onBookmark: onBookmark,
          ),
          const SizedBox(height: AppSpacing.tabBarSpacerCompact),
        ],
      ),
    );
  }
}

/// 实时转写列表：新片段进入后自动滚到底。
class _LiveList extends StatefulWidget {
  const _LiveList({required this.items, this.scrollController});

  final List<TranscriptItemView> items;
  final ScrollController? scrollController;

  @override
  State<_LiveList> createState() => _LiveListState();
}

class _LiveListState extends State<_LiveList> {
  late final ScrollController _controller =
      widget.scrollController ?? ScrollController();

  @override
  void didUpdateWidget(covariant _LiveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          '正在聆听，说话后这里会实时出现文字…',
          style: AppTextStyles.meta,
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.only(bottom: 10),
      itemCount: widget.items.length,
      itemBuilder: (BuildContext context, int index) =>
          TranscriptTile(item: widget.items[index]),
    );
  }
}
