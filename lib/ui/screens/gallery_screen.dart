/// 「屏幕目录」：对齐 HTML 的 `.screen-nav`，在 debug 构建可一键跳到任意一屏。
///
/// 只在 debug 构建注册路由（见 `lib/ui/router/app_router.dart`），
/// 13 个屏全部用 `docs/design-reference/smart-minutes-app.html` 的演示数据渲染，
/// 便于逐屏对照评审。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_data.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/filter_chips.dart';
import '../widgets/speaker_chips.dart';
import 'history_screen.dart';
import 'home_idle_screen.dart';
import 'minutes_screen.dart';
import 'profile_screen.dart';
import 'recording_screen.dart';
import 'transcript_screen.dart';

/// 目录条目。
class GalleryEntry {
  /// 构造条目。
  const GalleryEntry({required this.id, required this.label, required this.section});

  /// 屏号（s01…s13）。
  final String id;

  /// 名称。
  final String label;

  /// 分组标题。
  final String section;
}

/// 13 个屏（与 HTML `.screen-nav` 的顺序一致）。
const List<GalleryEntry> kGalleryEntries = <GalleryEntry>[
  GalleryEntry(id: 's01', label: '待机态 · 首页', section: '核心流程'),
  GalleryEntry(id: 's02', label: '录音中', section: '核心流程'),
  GalleryEntry(id: 's03', label: 'AI 会议纪要', section: '核心流程'),
  GalleryEntry(id: 's04', label: '历史记录', section: '核心流程'),
  GalleryEntry(id: 's05', label: '我的', section: '核心流程'),
  GalleryEntry(id: 's07', label: '完整转写', section: '核心流程'),
  GalleryEntry(id: 's06', label: '断线重连', section: '状态与边界'),
  GalleryEntry(id: 's08', label: '历史 · 空态', section: '状态与边界'),
  GalleryEntry(id: 's09', label: '历史 · 超长列表', section: '状态与边界'),
  GalleryEntry(id: 's10', label: '搜索无结果', section: '状态与边界'),
  GalleryEntry(id: 's11', label: '总结超长', section: '状态与边界'),
  GalleryEntry(id: 's12', label: '转写超长', section: '状态与边界'),
  GalleryEntry(id: 's13', label: '说话人过多', section: '状态与边界'),
];

/// 屏幕目录首页。
class GalleryScreen extends StatelessWidget {
  /// 构造目录页。
  const GalleryScreen({super.key, required this.onOpen});

  /// 打开某一屏（回传屏号）。
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('屏幕目录', style: AppTextStyles.sectionTitle),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: kGalleryEntries.length + 2,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) return const _GallerySectionTitle(text: '核心流程');
          if (index == 7) return const _GallerySectionTitle(text: '状态与边界');
          final int entryIndex = index <= 6 ? index - 1 : index - 2;
          return _GalleryButton(entry: kGalleryEntries[entryIndex], onOpen: onOpen);
        },
      ),
    );
  }
}

class _GallerySectionTitle extends StatelessWidget {
  const _GallerySectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(text, style: AppTextStyles.metaSmall.copyWith(color: AppColors.faint)),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.entry, required this.onOpen});

  final GalleryEntry entry;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(entry.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                Text(
                  entry.id.substring(1),
                  style: AppTextStyles.metaSmall.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(entry.label, style: AppTextStyles.settingTitle),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个屏的演示宿主：持有该屏交互所需的局部状态。
class GalleryScreenHost extends ConsumerStatefulWidget {
  /// 构造宿主。
  const GalleryScreenHost({
    super.key,
    required this.screenId,
    required this.onExit,
    required this.onOpenScreen,
  });

  /// 屏号。
  final String screenId;

  /// 退出（回到目录）。
  final VoidCallback onExit;

  /// 跳到另一屏（对齐 HTML `data-go`，如录音第 8 秒跳 s06）。
  final ValueChanged<String> onOpenScreen;

  @override
  ConsumerState<GalleryScreenHost> createState() => _GalleryScreenHostState();
}

class _GalleryScreenHostState extends ConsumerState<GalleryScreenHost> {
  static const List<String> _modes = <String>['会议', '访谈', '灵感'];
  static const List<String> _filters = <String>['全部', '今天', '本周', '已总结'];

  final ScrollController _liveScroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  Timer? _recTimer;
  int _modeIndex = 0;
  int _recSeconds = 0;
  int _recIndex = 0;
  bool _paused = false;
  bool _disconnected = false;
  int _filterIndex = 0;
  int _speakerFilter = 0;
  int _hitIndex = 3;
  bool _hitVisible = true;
  bool _diarization = true;
  bool _keepAudio = false;
  bool _abstractExpanded = false;
  bool _favorited = false;

  @override
  void initState() {
    super.initState();
    if (widget.screenId == 's02') {
      _startDemoRecording();
    }
    if (widget.screenId == 's10') {
      _search.text = '区块链';
    }
  }

  @override
  void didUpdateWidget(covariant GalleryScreenHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenId != widget.screenId) {
      _stopDemoRecording();
      if (widget.screenId == 's02') {
        _startDemoRecording();
      }
      if (widget.screenId == 's10') {
        _search.text = '区块链';
      }
    }
  }

  @override
  void dispose() {
    _stopDemoRecording();
    _liveScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _startDemoRecording() {
    _recSeconds = 0;
    _recIndex = 0;
    _paused = false;
    _disconnected = false;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) return;
      setState(() {
        _recSeconds++;
        // 与 HTML 一致：时间轴按 4 倍速推进（`parseT(t) <= recSec*4`）。
        while (_recIndex < kDemoTranscript.length &&
            kDemoTranscript[_recIndex].seconds <= _recSeconds * 4) {
          _recIndex++;
        }
      });
      // 第 8 秒模拟断线 → 跳 s06（对齐 HTML `data-go`）。
      // 注意：这里用 Toast 而不是 SnackBar —— 本 App 的每屏自带 TabBar、
      // 不套 Scaffold，`ScaffoldMessenger.showSnackBar` 会直接断言失败。
      if (_recSeconds == 8 && !_disconnected) {
        _disconnected = true;
        _toast('网络连接中断 · 已切到断线重连屏');
        widget.onOpenScreen('s06');
      }
    });
  }

  void _stopDemoRecording() {
    _recTimer?.cancel();
    _recTimer = null;
  }

  void _toast(String text) {
    ref.read(toastProvider.notifier).show(text, tone: ToastTone.success);
  }

  List<SpeakerChipView> _speakerChips(int count, {bool grayLast = false}) {
    return <SpeakerChipView>[
      for (int i = 1; i <= count; i++)
        SpeakerChipView(
          ordinal: i,
          label: grayLast && i == count ? '说话人 $i · 识别中' : '说话人 $i',
          gray: grayLast && i == count,
        ),
    ];
  }

  List<FilterChipView> _filterChips(int selected) {
    return <FilterChipView>[
      for (int i = 0; i < _filters.length; i++)
        FilterChipView(label: _filters[i], selected: i == selected),
    ];
  }

  List<FilterChipView> _speakerFilterChips(int selected) {
    return <FilterChipView>[
      FilterChipView(label: '全部', selected: selected == 0),
      for (int i = 1; i <= 3; i++)
        FilterChipView(label: '说话人 $i', ordinal: i, selected: selected == i),
    ];
  }

  String _clockText(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    if (m >= 60) {
      final int h = m ~/ 60;
      return '$h:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.screenId) {
      's01' => _buildS01(),
      's02' => _buildS02(),
      's03' => _buildS03(),
      's04' => _buildS04(),
      's05' => _buildS05(),
      's06' => _buildS06(),
      's07' => _buildS07(),
      's08' => _buildS08(),
      's09' => _buildS09(),
      's10' => _buildS10(),
      's11' => _buildS11(),
      's12' => _buildS12(),
      's13' => _buildS13(),
      _ => _buildS01(),
    };
  }

  HomeIdleScreen _buildS01() {
    return HomeIdleScreen.demo(
      onMicTap: () => widget.onExit(),
      onModeChanged: (int index) => setState(() => _modeIndex = index),
      onViewAll: () => _toast('打开历史记录'),
      onTabTap: (_) => widget.onExit(),
      onRecentTap: (int index) => _toast('打开最近记录 ${index + 1}'),
    );
  }

  RecordingScreen _buildS02() {
    return RecordingScreen(
      title: '录音中',
      subtitle: '${_modes[_modeIndex]}模式',
      clock: _clockText(_recSeconds),
      speakers: _speakerChips(3),
      items: demoTranscriptViews(take: _recIndex),
      liveTag: '自动滚动',
      paused: _paused,
      scrollController: _liveScroll,
      onClose: widget.onExit,
      onSettings: () => _toast('录音设置'),
      onPauseToggle: () => setState(() => _paused = !_paused),
      onStop: () => _toast('已结束并生成纪要'),
      onBookmark: () => _toast('已添加书签'),
      onTabTap: (_) => widget.onExit(),
    );
  }

  MinutesScreen _buildS03() {
    return MinutesScreen(
      generatedAt: '生成于 12:47',
      meetingTitle: 'Q3 产品规划评审',
      meetingMeta: '32 分钟 · 3 位说话人 · 今天 09:12',
      badgeText: '已完成',
      minutes: demoShortMinutesView(
        onOpenTranscript: () => _toast('打开完整转写'),
        onMore: (int index) => _toast('查看全部分节 ${index + 1}'),
      ),
      onClose: widget.onExit,
      onShare: () => _toast('分享链接已复制'),
      onExport: () => _toast('纪要已导出为 Markdown'),
      onFavorite: () => setState(() => _favorited = !_favorited),
      favorited: _favorited,
    );
  }

  HistoryScreen _buildS04() {
    return HistoryScreen(
      variant: HistoryVariant.list,
      filters: _filterChips(_filterIndex),
      selectedFilter: _filterIndex,
      onFilterChanged: (int index) => setState(() => _filterIndex = index),
      onFilterButton: () => _toast('筛选'),
      onTabTap: (_) => widget.onExit(),
      onStartRecording: widget.onExit,
      searchController: _search,
      onSearchChanged: (_) => setState(() {}),
      items: demoHistoryViews(
        onTap: (int index) => _toast('打开记录 ${index + 1}'),
        onMore: (int index) => _toast('更多操作 ${index + 1}'),
      ),
    );
  }

  ProfileScreen _buildS05() {
    return ProfileScreen(
      sections: <ProfileSectionView>[
        ProfileSectionView(
          title: '模型与转写',
          rows: <ProfileSettingView>[
            const ProfileSettingView(
              icon: Icons.auto_awesome_rounded,
              title: '纪要模型',
              subtitle: '摘要策略 · knowledge-extract',
              value: 'qwen3.7-plus',
            ),
            const ProfileSettingView(
              icon: Icons.translate_rounded,
              title: '转写语言',
              subtitle: '云端 ASR 识别语种',
              value: '中英文自动',
            ),
            ProfileSettingView(
              icon: Icons.groups_rounded,
              title: '说话人分离',
              subtitle: '声纹聚类 · 自动标注',
              toggle: true,
              toggleValue: _diarization,
              switchLabel: '说话人分离',
              onToggle: (bool value) => setState(() => _diarization = value),
            ),
          ],
        ),
        ProfileSectionView(
          title: '数据与导出',
          rows: <ProfileSettingView>[
            const ProfileSettingView(
              icon: Icons.description_outlined,
              title: '导出格式',
              subtitle: '纪要导出为文件',
              value: 'Markdown',
            ),
            ProfileSettingView(
              icon: Icons.wifi_off_rounded,
              title: '音频留存',
              subtitle: '转写后不保存原始音频',
              toggle: true,
              toggleValue: _keepAudio,
              switchLabel: '音频留存',
              onToggle: (bool value) => setState(() => _keepAudio = value),
            ),
          ],
        ),
      ],
      versionText: '版本 v1.0.0 · 端化运行',
      onSettings: () => _toast('设置'),
      onTabTap: (_) => widget.onExit(),
    );
  }

  RecordingScreen _buildS06() {
    return RecordingScreen(
      title: '录音中',
      subtitle: '会议模式',
      clock: '12:34',
      dimTitle: true,
      speakers: _speakerChips(3),
      items: demoTranscriptViews(take: 4, pendingLast: true),
      liveTag: '转写已暂停',
      liveTagPaused: true,
      paused: false,
      scrollController: _liveScroll,
      topOverlay: AppActionToast(
        title: '网络连接中断',
        subtitle: '正在本地缓存音频，恢复后自动续传',
        actionLabel: '重试',
        onAction: () => _toast('正在重试连接…'),
      ),
      onClose: widget.onExit,
      onSettings: () => _toast('录音设置'),
      onPauseToggle: () => _toast('暂停'),
      onStop: () => _toast('已结束并生成纪要'),
      onBookmark: () => _toast('已添加书签'),
      onTabTap: (_) => widget.onExit(),
    );
  }

  TranscriptScreen _buildS07() {
    return TranscriptScreen(
      meetingName: 'Q3 产品规划评审',
      infoText: '32 分钟 · 3 位说话人',
      charCountText: '1,860 字',
      filters: _speakerFilterChips(_speakerFilter),
      selectedFilter: _speakerFilter,
      onFilterChanged: (int index) => setState(() => _speakerFilter = index),
      items: demoTranscriptViews(),
      onBack: widget.onExit,
      onSearch: () => _toast('搜索转写'),
      onCopyAll: () => _toast('全文已复制到剪贴板'),
      onExportMarkdown: () => _toast('转写已导出 Markdown'),
    );
  }

  HistoryScreen _buildS08() {
    return HistoryScreen(
      variant: HistoryVariant.empty,
      filters: _filterChips(0),
      selectedFilter: 0,
      onFilterChanged: (_) {},
      onFilterButton: () {},
      onTabTap: (_) => widget.onExit(),
      onStartRecording: widget.onExit,
    );
  }

  HistoryScreen _buildS09() {
    return HistoryScreen(
      variant: HistoryVariant.longList,
      subtitle: '共 128 条 · 约 64 小时',
      sortLabel: '最近优先',
      onSort: () => _toast('切换排序'),
      filters: _filterChips(0),
      selectedFilter: 0,
      onFilterChanged: (int index) => setState(() => _filterIndex = index),
      onFilterButton: () => _toast('筛选'),
      onTabTap: (_) => widget.onExit(),
      onStartRecording: widget.onExit,
      searchController: _search,
      loadMoreText: '正在加载更多 · 已显示 24 / 128',
      groups: demoLongHistoryGroups(
        onTap: (int index) => _toast('打开记录 ${index + 1}'),
        onMore: (int index) => _toast('更多操作 ${index + 1}'),
      )
          .map(
            (group) => HistoryGroupView(day: group.day, items: group.items),
          )
          .toList(growable: false),
    );
  }

  HistoryScreen _buildS10() {
    return HistoryScreen(
      variant: HistoryVariant.searchEmpty,
      keyword: '区块链',
      filters: _filterChips(0),
      selectedFilter: 0,
      onFilterChanged: (int index) => setState(() => _filterIndex = index),
      onFilterButton: () => _toast('筛选'),
      onTabTap: (_) => widget.onExit(),
      onStartRecording: widget.onExit,
      searchController: _search,
      onSearchClear: () => _toast('已清空搜索'),
      onClearFilters: () => _toast('已清空筛选条件'),
      onSearchAllTime: () => _toast('已搜索全部时间'),
    );
  }

  MinutesScreen _buildS11() {
    return MinutesScreen(
      generatedAt: '生成于 12:47',
      meetingTitle: 'Q3 产品规划评审',
      meetingMeta: '3 小时 12 分钟 · 8 位说话人 · 今天 09:12',
      badgeText: '已完成',
      minutes: demoLongMinutesView(
        expanded: _abstractExpanded,
        onExpandAbstract: () => setState(() => _abstractExpanded = !_abstractExpanded),
        onOpenTranscript: () => _toast('打开完整转写'),
        onMore: (int index) => _toast('查看全部分节 ${index + 1}'),
      ),
      onClose: widget.onExit,
      onShare: () => _toast('分享链接已复制'),
      onExport: () => _toast('纪要已导出为 Markdown'),
      onFavorite: () => setState(() => _favorited = !_favorited),
      favorited: _favorited,
    );
  }

  TranscriptScreen _buildS12() {
    return TranscriptScreen(
      meetingName: 'Q3 产品规划评审',
      infoText: '3 小时 12 分钟 · 8 位说话人',
      charCountText: '28,640 字',
      filters: _speakerFilterChips(_speakerFilter),
      selectedFilter: _speakerFilter,
      onFilterChanged: (int index) => setState(() => _speakerFilter = index),
      items: demoLongTranscriptViews(),
      segmentLoadingText: '分段加载中 · 已显示 1,240 / 3,480 段',
      hit: _hitVisible
          ? TranscriptHitView(
              total: 12,
              current: _hitIndex,
              keyword: '激活',
              onPrev: () => setState(() => _hitIndex = _hitIndex > 1 ? _hitIndex - 1 : 12),
              onNext: () => setState(() => _hitIndex = _hitIndex < 12 ? _hitIndex + 1 : 1),
              onClose: () => setState(() => _hitVisible = false),
            )
          : null,
      onExpandSegment: (int index) => _toast('展开第 ${index + 1} 段'),
      onBack: widget.onExit,
      onSearch: () => _toast('搜索转写'),
      onCopyAll: () => _toast('全文已复制到剪贴板'),
      onExportMarkdown: () => _toast('转写已导出 Markdown'),
    );
  }

  RecordingScreen _buildS13() {
    return RecordingScreen(
      title: '录音中',
      subtitle: '会议模式 · 已识别 8 人',
      clock: '2:15:08',
      speakers: _speakerChips(8, grayLast: true),
      items: demoTranscriptViews(take: 3),
      liveTag: '自动滚动',
      paused: false,
      showBackToBottom: true,
      onBackToBottom: () => _toast('已回到底部'),
      scrollController: _liveScroll,
      onClose: widget.onExit,
      onSettings: () => _toast('录音设置'),
      onPauseToggle: () => _toast('暂停'),
      onStop: () => _toast('已结束并生成纪要'),
      onBookmark: () => _toast('已添加书签'),
      onTabTap: (_) => widget.onExit(),
    );
  }
}
