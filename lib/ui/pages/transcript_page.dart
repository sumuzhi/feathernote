/// 完整转写页（屏 07 常规 / 屏 12 超长）。
///
/// 超长态（≥200 段）自动补上「分段加载中」胶囊；页内搜索命中后展示命中条
/// （`找到 N 处「关键词」` + `i / N` + 上/下一处 + 关闭）并高亮命中片段。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../providers/audio_player_controller.dart';
import '../screens/transcript_screen.dart';
import '../theme/app_theme.dart';
import '../utils/export_destination.dart';
import '../utils/exporter.dart';
import '../utils/formatters.dart';
import '../utils/speaker_view.dart';
import '../widgets/app_toast.dart';
import '../widgets/export_format_sheet.dart';
import '../widgets/filter_chips.dart';
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_tile.dart';

/// 超出该段数时展示「分段加载」胶囊（对齐屏 12 的长内容形态）。
const int kLongTranscriptThreshold = 200;

/// 分页窗口：初始渲染条数，触底按页扩窗。
///
/// 真分页修复两件事：① 数千段一次性渲染导致滚动卡顿；② 旧「分段加载中」
/// 胶囊是纯装饰（≥200 段即永远显示），被误读为「卡在加载中」。
const int kTranscriptPageSize = 80;

/// 完整转写页。
class TranscriptPage extends ConsumerStatefulWidget {
  /// 构造转写页。
  ///
  /// [initialMeeting] 为来源页（纪要页）**已加载**的会议对象：传入则首帧即渲染
  /// 内容，不再先走一次 loading / 空态再异步填充（消除「闪一下」）。
  const TranscriptPage({super.key, required this.meetingId, this.initialMeeting});

  /// 会议 ID。
  final String meetingId;

  /// 来源页预热的会议（可为 null：深链 / 屏幕目录直接进入）。
  final Meeting? initialMeeting;

  @override
  ConsumerState<TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends ConsumerState<TranscriptPage>
    with RouteAware {
  Meeting? _meeting;
  List<TranscriptSegment> _segments = const <TranscriptSegment>[];
  List<Speaker> _speakers = const <Speaker>[];
  StreamSubscription<List<TranscriptSegment>>? _subscription;
  bool _loading = true;
  int _filter = 0;
  String _keyword = '';
  List<int> _hits = const <int>[];
  int _hitCursor = 0;

  // ── 长列表性能（真分页 + 派生缓存）─────────────────────────────────
  /// 渲染窗口大小（过滤后最多显示的条数），触底经 [_onLoadMore] 扩窗。
  int _visibleCount = kTranscriptPageSize;

  /// 每段说话人序号缓存（segments/speakers 变化时重算，避免每次 build O(n) 查询）。
  List<int> _ordinals = const <int>[];

  /// 过滤后的总段数（跟随 _filter / _segments）。
  int _filteredTotal = 0;

  /// 全文字数缓存（原实现在每次 build 对全文跑正则——播放位置 tick 下 O(总字数)）。
  int _charCount = 0;

  /// 说话人 chips 缓存。
  List<SpeakerChipView> _chips = const <SpeakerChipView>[];

  /// 触底扩窗节流戳。
  DateTime _lastLoadMoreAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 重算派生数据（segments / speakers 变化时调用；绝不放进 build）。
  ///
  /// ⚠️ 不 clamp 窗口：`_load` 完成时段落可能尚未从 watchSegments 流到达
  /// （此时 filteredTotal=0），若在此收缩窗口会把渲染窗口永久压成 0 ——
  /// 「列表一片空白」的根因。窗口切片由 Screen 端 `min(visibleCount, len)` 完成。
  void _recomputeDerived() {
    _ordinals = <int>[
      for (final TranscriptSegment segment in _segments)
        speakerViewFor(speakerId: segment.speakerId, speakers: _speakers).ordinal,
    ];
    _filteredTotal = _countFiltered();
    _chips = _computeChips();
    _charCount = _segments.fold<int>(
      0,
      (int sum, TranscriptSegment s) =>
          sum + s.text.replaceAll(RegExp(r'\s'), '').length,
    );
  }

  int _countFiltered() {
    if (_filter == 0) return _segments.length;
    int count = 0;
    for (final int ordinal in _ordinals) {
      if (ordinal == _filter) count++;
    }
    return count;
  }

  /// 触底扩窗（节流：滚动事件连续触发，200ms 内只受理一次）。
  void _onLoadMore() {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastLoadMoreAt) < const Duration(milliseconds: 200)) {
      return;
    }
    if (_visibleCount >= _filteredTotal) return;
    _lastLoadMoreAt = now;
    setState(() {
      _visibleCount =
          (_visibleCount + kTranscriptPageSize).clamp(0, _filteredTotal);
    });
  }

  @override
  void initState() {
    super.initState();
    // 首帧预热：数据已在内存中时，绝不再走一次「空态 → 内容」。
    final Meeting? seed = widget.initialMeeting;
    if (seed != null) {
      _meeting = seed;
      _segments = seed.segments;
      _speakers = seed.speakers;
      _loading = false;
      _recomputeDerived();
    }
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅路由事件：页面被退出（pop）时停止录音回放。
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPop() {
    super.didPop();
    // 退出转写页 → 停止回放（音频文件保持归档，随时可回再播）。
    unawaited(ref.read(audioPlayerControllerProvider.notifier).stop());
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    unawaited(_subscription?.cancel());
    // 播放器 provider 在页面移除监听者后会自动 dispose，那里会释放 AudioPlayer。
    // 不在 State.dispose() 里读 ref（Riverpod 此时已不允许）。
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = await ref.read(backendProvider.future);
      final Meeting? meeting = await api.getMeeting(widget.meetingId);
      if (!mounted) return;
      setState(() {
        // 不因一次 null / 旧数据把已预热的内容清空。
        _meeting = meeting ?? _meeting;
        if (meeting != null) _speakers = meeting.speakers;
        _loading = false;
        _recomputeDerived();
      });
      _subscription = api.watchSegments(widget.meetingId).listen(
        (List<TranscriptSegment> segments) {
          if (!mounted) return;
          setState(() {
            _segments = segments;
            if (_speakers.isEmpty && segments.isNotEmpty) {
              _speakers = deriveSpeakers(segments, meetingId: widget.meetingId);
            }
            _recomputeDerived();
            if (_keyword.isNotEmpty) _recomputeHits();
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ref.read(toastProvider.notifier).show(
            '转写加载失败：$error',
            tone: ToastTone.warning,
          );
    }
  }

  void _recomputeHits() {
    final List<int> hits = <int>[];
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].text.contains(_keyword)) hits.add(i);
    }
    _hits = hits;
    _hitCursor = hits.isEmpty ? 0 : 1;
  }

  /// 唯一的说话人过滤 chip（按序号升序）。
  List<SpeakerChipView> _computeChips() {
    final Map<int, String> byOrdinal = <int, String>{};
    for (final TranscriptSegment segment in _segments) {
      final SpeakerView view = speakerViewFor(
        speakerId: segment.speakerId,
        speakers: _speakers,
      );
      byOrdinal.putIfAbsent(view.ordinal, () => view.name);
    }
    final List<int> keys = byOrdinal.keys.toList()..sort();
    return <SpeakerChipView>[
      for (final int ordinal in keys)
        SpeakerChipView(ordinal: ordinal, label: byOrdinal[ordinal]!),
    ];
  }

  List<TranscriptItemView> _viewItems(AudioPlayerState audioState) =>
      <TranscriptItemView>[
        for (int i = 0; i < _segments.length; i++) _viewAt(i, audioState),
      ];

  TranscriptItemView _viewAt(int index, AudioPlayerState audioState) {
    final TranscriptSegment segment = _segments[index];
    final SpeakerView view = speakerViewFor(
      speakerId: segment.speakerId,
      speakers: _speakers,
    );
    final bool highlight = _hits.isNotEmpty && _hits[_hitCursor - 1] == index;
    final bool active = audioState.isSegmentActive(segment.segmentId, segment.startTime);
    final bool playing = audioState.isSegmentPlaying(segment.segmentId, segment.startTime);
    // 图标跟随播放组件的生命周期：自动停后的满格宽限期内组件仍在渲染，
    // 图标保持「暂停」样式，与进度条/时间一起同时消失（不能提前切回「播放」）。
    final bool iconShowsPause = playing || (active && audioState.justFinished);
    // 段内进度与已播时长：当前段才计算，其余场景恒为默认值。
    final int segDuration = segment.endTime - segment.startTime;
    final int played =
        (audioState.currentPositionMs - segment.startTime).clamp(0, segDuration > 0 ? segDuration : 0);
    return TranscriptItemView(
      ordinal: view.ordinal,
      speakerLabel: view.name,
      timeLabel: formatClock(segment.startTime),
      text: segment.text,
      segmentId: segment.segmentId,
      startTimeMs: segment.startTime,
      endTimeMs: segment.endTime,
      highlight: highlight,
      playActive: active,
      isPlaying: iconShowsPause,
      playProgress: segDuration > 0 ? played / segDuration : 0,
      playPositionLabel: formatClock(played),
      playDurationLabel: formatClock(segDuration),
      expandNote: highlight ? '展开这段 · ${formatCharCount(segment.text.length)}' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // loading → 内容做淡入过渡，避免硬切闪屏（切页过渡见 app_router）。
    return AnimatedSwitcher(
      duration: AppDuration.fade,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey<String>(_loading ? 'loading' : 'content'),
        child: _loading ? const Center(child: CircularProgressIndicator()) : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    // 在 build 里显式 watch：保证「播放状态变化 → 页面重建」这条依赖一定注册，
    // 不依赖 `_viewAt` 是否被调用（列表为空时它一次都不会跑到）。
    final AudioPlayerState audioState = ref.watch(audioPlayerControllerProvider);
    final Meeting? meeting = _meeting;
    final List<TranscriptItemView> items = _viewItems(audioState);
    final bool hasMore = _visibleCount < _filteredTotal;
    final int shown = hasMore ? _visibleCount : _filteredTotal;

    return TranscriptScreen(
      meetingName: meeting?.title ?? '完整转写',
      infoText: formatTranscriptInfo(
        durationMs: meeting?.durationMs ?? 0,
        speakerCount: meeting?.speakerCount ?? _chips.length,
      ),
      charCountText: formatCharCount(_charCount),
      filters: <FilterChipView>[
        FilterChipView(label: '全部', selected: _filter == 0),
        for (final SpeakerChipView chip in _chips)
          FilterChipView(
            label: chip.label,
            ordinal: chip.ordinal,
            selected: _filter == chip.ordinal,
          ),
      ],
      selectedFilter: _filter,
      onFilterChanged: (int index) => setState(() {
        _filter = index == 0 ? 0 : _chips[index - 1].ordinal;
        // 切换说话人 → 窗口重置，从第一页重新开始。
        _visibleCount = kTranscriptPageSize;
        _filteredTotal = _countFiltered();
      }),
      items: items,
      hit: _hits.isEmpty
          ? null
          : TranscriptHitView(
              total: _hits.length,
              current: _hitCursor,
              keyword: _keyword,
              onPrev: () => setState(
                () => _hitCursor = _hitCursor > 1 ? _hitCursor - 1 : _hits.length,
              ),
              onNext: () => setState(
                () => _hitCursor = _hitCursor < _hits.length ? _hitCursor + 1 : 1,
              ),
              onClose: () => setState(() {
                _keyword = '';
                _hits = const <int>[];
                _hitCursor = 0;
              }),
            ),
      // 诚实文案：窗口未满 → 「上滑加载更多 · N / M」；全部加载完 → 不再显示
      // （旧实现 ≥200 段就永久显示「分段加载中」，被误读为卡死在加载）。
      segmentLoadingText: _segments.length >= kLongTranscriptThreshold && hasMore
          ? '上滑加载更多 · 已显示 ${formatThousands(shown)} / ${formatThousands(_filteredTotal)} 段'
          : null,
      visibleCount: _visibleCount,
      onLoadMore: hasMore ? _onLoadMore : null,
      onExpandSegment: (int index) => _toast('展开第 ${index + 1} 段'),
      onPlaySegment: (TranscriptItemView item) => _onPlaySegment(item),
      // 返回 = 压栈 pop 回纪要页；无栈（深链冷启动）时兜底 go。
      onBack: () => context.canPop()
          ? context.pop()
          : context.go('/meeting/${widget.meetingId}'),
      onSearch: () => unawaited(_promptSearch()),
      onCopyAll: () => unawaited(_copyAll()),
      onExportMarkdown: () => unawaited(_exportMarkdown(meeting)),
    );
  }

  Future<void> _promptSearch() async {
    final TextEditingController controller = TextEditingController(text: _keyword);
    final String? keyword = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('在转写中搜索'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入关键词，如「激活」'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _keyword = keyword ?? '';
      _recomputeHits();
    });
    if (_keyword.isNotEmpty && _hits.isEmpty) {
      _toast('未找到「$_keyword」');
    }
  }

  Future<void> _copyAll() async {
    final String text = _segments
        .map((TranscriptSegment s) => '${formatClock(s.startTime)} ${s.text}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(
          '全文已复制到剪贴板',
          tone: ToastTone.success,
        );
  }

  Future<void> _exportMarkdown(Meeting? meeting) async {
    final ExportFormat? format = await showExportFormatSheet(context);
    if (format == null || !mounted) return;
    final ExportDestination destination = await loadExportDestination();
    final String content = _segments
        .map((TranscriptSegment s) => '- **${formatClock(s.startTime)}** ${s.text}')
        .join('\n');
    try {
      final String path = await exportMeeting(
        fileName: '${meeting?.title ?? 'transcript'}-转写',
        markdown: content,
        format: format,
        destination: destination,
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
            '已导出：$path',
            tone: ToastTone.success,
          );
    } on ExportCancelledException {
      // 用户在系统「另存为」取消，不打扰。
      return;
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('导出失败：$error', tone: ToastTone.warning);
    }
  }

  /// 播放指定条目。
  ///
  /// ⚠️ 入参是**条目本身**（含原始毫秒）：说话人过滤后列表下标与全量
  /// `_segments` 不再一一对应，按 index 取会播错段。
  Future<void> _onPlaySegment(TranscriptItemView item) async {
    await ref.read(audioPlayerControllerProvider.notifier).playSegment(
      meetingId: widget.meetingId,
      segmentId: item.segmentId,
      startMs: item.startTimeMs,
      endMs: item.endTimeMs,
    );
  }

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);
}
