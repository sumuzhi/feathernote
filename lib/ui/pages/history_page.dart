/// 历史记录页（屏 04 / 08 / 09 / 10）。
///
/// 变体由数据推导：
/// - 无记录 → 空态（08）；
/// - 有搜索词但零命中 → 搜索无结果（10）；
/// - 记录数 ≥ 12 → 超长列表，按日分组并带「正在加载更多」（09）；
/// - 其余 → 普通列表（04）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/history_screen.dart';
import '../utils/formatters.dart';
import '../widgets/filter_chips.dart';
import '../widgets/history_card.dart';

/// 历史记录页。
class HistoryPage extends ConsumerStatefulWidget {
  /// 构造历史页。
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  static const List<String> _filters = <String>['全部', '今天', '本周', '已总结'];
  static const int _longListThreshold = 12;

  final TextEditingController _search = TextEditingController();
  final ScrollController _listScroll = ScrollController();
  int _filterIndex = 0;
  String _query = '';

  /// 滚动位置是否已恢复（数据异步到达前不跳，避免 clamp 到 0）。
  bool _scrollRestored = false;

  @override
  void initState() {
    super.initState();
    // 恢复上次的筛选 / 搜索 / 滚动位置（go_router 的 go() 会销毁本页 State）。
    final HistoryUiCache cache = ref.read(historyUiCacheProvider);
    _filterIndex = cache.filterIndex;
    _query = cache.query;
    _search.text = cache.query;
    _listScroll.addListener(() {
      if (_listScroll.hasClients) {
        ref.read(historyUiCacheProvider).scrollOffset = _listScroll.offset;
      }
    });
    _restoreScrollWhenReady();
  }

  /// 数据 / 列表就绪后恢复滚动位置（逐帧重试直到可滚动）。
  void _restoreScrollWhenReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrollRestored) return;
      if (!_listScroll.hasClients) {
        _restoreScrollWhenReady();
        return;
      }
      final double target = ref.read(historyUiCacheProvider).scrollOffset;
      if (target <= 0) {
        _scrollRestored = true;
        return;
      }
      final double max = _listScroll.position.maxScrollExtent;
      if (max <= 0) {
        // 数据尚未加载（列表为空），等下一帧再试。
        _restoreScrollWhenReady();
        return;
      }
      _listScroll.jumpTo(target.clamp(0.0, max));
      _scrollRestored = true;
    });
  }

  /// 变更筛选 / 搜索：写回缓存并回到顶部（内容已变，原位置无意义）。
  void _setFilterState(VoidCallback mutate) {
    setState(mutate);
    final HistoryUiCache cache = ref.read(historyUiCacheProvider);
    cache.filterIndex = _filterIndex;
    cache.query = _query;
    cache.scrollOffset = 0;
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  @override
  void dispose() {
    _listScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  List<MeetingSummary> _filtered(List<MeetingSummary> source, DateTime now) {
    final String query = _query.trim().toLowerCase();
    return source.where((MeetingSummary item) {
      final bool passFilter = switch (_filterIndex) {
        1 => _isSameDay(item.createdAt, now),
        2 => now.difference(item.createdAt).inDays < 7,
        3 => item.hasMinutes,
        _ => true,
      };
      if (!passFilter) return false;
      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          item.minutesExcerpt.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> asyncMeetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> all = asyncMeetings.value ?? const <MeetingSummary>[];
    final DateTime now = DateTime.now();
    final List<MeetingSummary> filtered = _filtered(all, now);

    final HistoryVariant variant;
    if (all.isEmpty) {
      variant = HistoryVariant.empty;
    } else if (_query.trim().isNotEmpty && filtered.isEmpty) {
      variant = HistoryVariant.searchEmpty;
    } else if (filtered.length >= _longListThreshold) {
      variant = HistoryVariant.longList;
    } else {
      variant = HistoryVariant.list;
    }

    final List<HistoryGroupView> groups = <HistoryGroupView>[
      for (final _DayBucket bucket in _groupByDay(filtered, now))
        HistoryGroupView(
          day: bucket.day,
          items: <HistoryItemView>[
            for (int i = 0; i < bucket.items.length; i++)
              _toView(
                bucket.items[i],
                now,
                cut: i == bucket.items.length - 1 && bucket.isLastBucket,
              ),
          ],
        ),
    ];

    return HistoryScreen(
      variant: variant,
      filters: <FilterChipView>[
        for (int i = 0; i < _filters.length; i++)
          FilterChipView(label: _filters[i], selected: i == _filterIndex),
      ],
      selectedFilter: _filterIndex,
      onFilterChanged: (int index) => _setFilterState(() => _filterIndex = index),
      onFilterButton: () =>
          _setFilterState(() => _filterIndex = (_filterIndex + 1) % _filters.length),
      onTabTap: (int index) {
        switch (index) {
          case 0:
            context.go('/');
          case 2:
            context.go('/profile');
          default:
            break;
        }
      },
      onStartRecording: () => context.go('/'),
      searchController: _search,
      scrollController: _listScroll,
      onSearchChanged: (String value) => _setFilterState(() => _query = value),
      onSearchClear: () {
        _search.clear();
        _setFilterState(() => _query = '');
      },
      keyword: _query.trim(),
      items: <HistoryItemView>[
        for (final MeetingSummary item in filtered) _toView(item, now),
      ],
      groups: groups,
      subtitle: variant == HistoryVariant.longList
          ? '共 ${filtered.length} 条 · 约 ${_totalHours(filtered)} 小时'
          : null,
      loadMoreText: '正在加载更多 · 已显示 ${filtered.length} / ${all.length}',
      onClearFilters: () => _setFilterState(() {
        _filterIndex = 0;
        _search.clear();
        _query = '';
      }),
      onSearchAllTime: () => _setFilterState(() => _filterIndex = 0),
      selectedTab: 1,
    );
  }

  HistoryItemView _toView(MeetingSummary item, DateTime now, {bool cut = false}) {
    // 导入会议：badge「导入」/「导入失败」+ 处理中角标（设计 §8.1）。
    final bool imported = item.source == MeetingSource.imported;
    final bool importProcessing = imported &&
        (item.importStatus == ImportStatus.importPending ||
            item.importStatus == ImportStatus.extracting ||
            item.importStatus == ImportStatus.transcribing ||
            item.importStatus == ImportStatus.minutes);
    final bool importFailed = imported && item.importStatus == ImportStatus.failed;
    return HistoryItemView(
      title: item.title,
      description: item.minutesExcerpt.isEmpty
          ? (importFailed
              ? '导入失败，可进入详情页重试'
              : (imported ? '来自视频 / 音频导入' : '暂无纪要，停止录音后自动生成'))
          : item.minutesExcerpt,
      meta:
          '${formatDurationCn(item.durationMs)} · ${formatDayTime(item.createdAt, now: now)} · ${formatPeople(item.speakerCount)}',
      badge: importFailed
          ? HistoryBadge.importFailed
          : (imported ? HistoryBadge.imported : (item.hasMinutes ? HistoryBadge.summarized : HistoryBadge.done)),
      processing: importProcessing,
      cut: cut,
      dimBadge: cut,
      onTap: () => context.push('/meeting/${item.id}'),
      onMore: () => _showMoreMenu(item),
      // 左滑删除：稳定 key（会议 ID）+ 确认框 + 确认后真删。
      dismissKey: item.id,
      confirmDismiss: () => _confirmDeleteDialog(item),
      onDismissed: () => _deleteConfirmed(item),
    );
  }

  /// 删除确认框：返回 true = 用户确认删除。
  Future<bool> _confirmDeleteDialog(MeetingSummary item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('「${item.title}」及其纪要与转写将一并删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 已确认删除：调后端并解除可能的首页生成锁。
  Future<void> _deleteConfirmed(MeetingSummary item) async {
    final backend = await ref.read(backendProvider.future);
    await backend.deleteMeeting(item.id);
  }

  Future<void> _showMoreMenu(MeetingSummary item) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _rename(item);
    } else {
      await _delete(item);
    }
  }

  Future<void> _rename(MeetingSummary item) async {
    final TextEditingController controller = TextEditingController(text: item.title);
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || next == null || next.isEmpty) return;
    final backend = await ref.read(backendProvider.future);
    await backend.updateMeeting(item.id, title: next);
  }

  Future<void> _delete(MeetingSummary item) async {
    if (!mounted) return;
    final bool ok = await _confirmDeleteDialog(item);
    if (!mounted || !ok) return;
    await _deleteConfirmed(item);
  }

  int _totalHours(List<MeetingSummary> list) {
    int totalMs = 0;
    for (final MeetingSummary item in list) {
      totalMs += item.durationMs;
    }
    return totalMs ~/ 3600000;
  }
}

class _DayBucket {
  const _DayBucket({required this.day, required this.items, required this.isLastBucket});

  final String day;
  final List<MeetingSummary> items;
  final bool isLastBucket;
}

List<_DayBucket> _groupByDay(List<MeetingSummary> list, DateTime now) {
  final List<_DayBucket> buckets = <_DayBucket>[];
  String? currentDay;
  List<MeetingSummary> current = <MeetingSummary>[];
  for (final MeetingSummary item in list) {
    final String day = formatDayLabel(item.createdAt, now: now);
    if (currentDay != day) {
      if (currentDay != null) {
        buckets.add(_DayBucket(day: currentDay, items: current, isLastBucket: false));
      }
      currentDay = day;
      current = <MeetingSummary>[item];
    } else {
      current.add(item);
    }
  }
  if (currentDay != null) {
    buckets.add(_DayBucket(day: currentDay, items: current, isLastBucket: true));
  }
  return buckets;
}
