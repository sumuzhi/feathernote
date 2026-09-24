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
import '../screens/transcript_screen.dart';
import '../utils/exporter.dart';
import '../utils/formatters.dart';
import '../utils/speaker_view.dart';
import '../widgets/app_toast.dart';
import '../widgets/filter_chips.dart';
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_tile.dart';

/// 超出该段数时展示「分段加载中」胶囊（对齐屏 12 的长内容形态）。
const int kLongTranscriptThreshold = 200;

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

class _TranscriptPageState extends ConsumerState<TranscriptPage> {
  Meeting? _meeting;
  List<TranscriptSegment> _segments = const <TranscriptSegment>[];
  List<Speaker> _speakers = const <Speaker>[];
  StreamSubscription<List<TranscriptSegment>>? _subscription;
  bool _loading = true;
  int _filter = 0;
  String _keyword = '';
  List<int> _hits = const <int>[];
  int _hitCursor = 0;

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
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
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
      });
      _subscription = api.watchSegments(widget.meetingId).listen(
        (List<TranscriptSegment> segments) {
          if (!mounted) return;
          setState(() {
            _segments = segments;
            if (_speakers.isEmpty && segments.isNotEmpty) {
              _speakers = deriveSpeakers(segments, meetingId: widget.meetingId);
            }
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
  List<SpeakerChipView> _chipViews() {
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

  List<TranscriptItemView> _allItems() => <TranscriptItemView>[
        for (int i = 0; i < _segments.length; i++) _viewAt(i),
      ];

  TranscriptItemView _viewAt(int index) {
    final TranscriptSegment segment = _segments[index];
    final SpeakerView view = speakerViewFor(
      speakerId: segment.speakerId,
      speakers: _speakers,
    );
    final bool highlight = _hits.isNotEmpty && _hits[_hitCursor - 1] == index;
    return TranscriptItemView(
      ordinal: view.ordinal,
      speakerLabel: view.name,
      timeLabel: formatClock(segment.startTime),
      text: segment.text,
      highlight: highlight,
      expandNote: highlight ? '展开这段 · ${formatCharCount(segment.text.length)}' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final Meeting? meeting = _meeting;
    final List<TranscriptItemView> items = _allItems();
    final List<SpeakerChipView> chips = _chipViews();
    final int charCount = _segments.fold<int>(0, (int sum, TranscriptSegment s) => sum + s.text.replaceAll(RegExp(r'\s'), '').length);

    return TranscriptScreen(
      meetingName: meeting?.title ?? '完整转写',
      infoText: formatTranscriptInfo(
        durationMs: meeting?.durationMs ?? 0,
        speakerCount: meeting?.speakerCount ?? chips.length,
      ),
      charCountText: formatCharCount(charCount),
      filters: <FilterChipView>[
        FilterChipView(label: '全部', selected: _filter == 0),
        for (final SpeakerChipView chip in chips)
          FilterChipView(
            label: chip.label,
            ordinal: chip.ordinal,
            selected: _filter == chip.ordinal,
          ),
      ],
      selectedFilter: _filter,
      onFilterChanged: (int index) => setState(() {
        _filter = index == 0 ? 0 : chips[index - 1].ordinal;
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
      segmentLoadingText: _segments.length >= kLongTranscriptThreshold
          ? '分段加载中 · 已显示 ${formatThousands(_segments.length)} 段'
          : null,
      onExpandSegment: (int index) => _toast('展开第 ${index + 1} 段'),
      onBack: () => context.go('/meeting/${widget.meetingId}'),
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
    final String content = _segments
        .map((TranscriptSegment s) => '- **${formatClock(s.startTime)}** ${s.text}')
        .join('\n');
    try {
      final String path = await exportTextFile(
        fileName: '${meeting?.title ?? 'transcript'}-转写',
        content: content,
        extension: '.md',
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
            '已导出：$path',
            tone: ToastTone.success,
          );
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('导出失败：$error', tone: ToastTone.warning);
    }
  }

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);
}
