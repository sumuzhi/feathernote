/// 首页：待机态（屏 01）与录音态（屏 02 / 06 / 13）同页切换。
///
/// 页面只做「状态 → 视图数据」的翻译，视觉全部交给 `lib/ui/screens/`，
/// 以便「屏幕目录」能用同一套组件渲染 13 个屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/meeting.dart';
import '../../domain/recording_mode.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../providers/recorder_controller.dart';
import '../screens/home_idle_screen.dart';
import '../screens/recording_screen.dart';
import '../utils/formatters.dart';
import '../utils/placeholders.dart';
import '../utils/speaker_view.dart';
import '../widgets/app_toast.dart';
import '../widgets/history_card.dart';
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_tile.dart';

/// 首页。
class HomePage extends ConsumerStatefulWidget {
  /// 构造首页。
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _liveScroll = ScrollController();
  bool _starting = false;

  @override
  void dispose() {
    _liveScroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await ref.read(recorderProvider.notifier).startRecording();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final String? meetingId = await ref.read(recorderProvider.notifier).stopAndGenerate();
    if (!mounted) return;
    if (meetingId != null) {
      context.go('/meeting/$meetingId');
      return;
    }
    // 兜底：理论上录音中必有 meetingId；若异常为空，也要给用户明确去处。
    ref.read(toastProvider.notifier).show(
          '本次录音未生成会议记录，请到历史页查看',
          tone: ToastTone.warning,
        );
    context.go('/history');
  }

  Future<void> _close() async {
    final RecorderUiState state = ref.read(recorderProvider);
    if (!state.isActive) return;
    final bool discard = await _confirmDiscard();
    if (!mounted || !discard) return;
    await ref.read(recorderProvider.notifier).discard();
  }

  Future<bool> _confirmDiscard() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('结束本次录音？'),
        content: const Text('选择「丢弃」会删除本次录音与已转写内容；选择「取消」继续录音。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final RecorderUiState recorder = ref.watch(recorderProvider);
    if (!recorder.isActive) {
      return _buildIdle(context);
    }
    return _buildRecording(context, recorder);
  }

  Widget _buildIdle(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> meetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> list = meetings.value ?? const <MeetingSummary>[];
    final DateTime now = DateTime.now();
    final int todayMinutes = _todayMinutes(list, now);
    final List<HistoryItemView> recent = <HistoryItemView>[
      for (int i = 0; i < list.length && i < 2; i++)
        HistoryItemView(
          title: list[i].title,
          description:
              '${formatDurationCn(list[i].durationMs)} · ${formatDayTime(list[i].createdAt, now: now)}',
          meta: '',
          badge: list[i].hasMinutes ? HistoryBadge.summarized : HistoryBadge.done,
          onTap: () => context.go('/meeting/${list[i].id}'),
        ),
    ];
    final RecordingMode mode = ref.watch(recorderProvider).mode;

    return HomeIdleScreen(
      greeting: '${greetingFor(now)}，$kUserDisplayName',
      userName: kUserDisplayName,
      heroStatusText: _starting ? '启动中' : '待机中',
      heroStatusTail: '今日已记录 $todayMinutes 分钟',
      modes: const <String>['会议', '访谈', '灵感'],
      selectedMode: mode.index,
      recentItems: recent,
      onMicTap: _start,
      onModeChanged: (int index) =>
          ref.read(recorderProvider.notifier).setMode(RecordingMode.values[index]),
      onViewAll: () => context.go('/history'),
      onAvatarTap: () => context.go('/profile'),
      onTabTap: _onTabTap,
      selectedTab: 0,
    );
  }

  Widget _buildRecording(BuildContext context, RecorderUiState state) {
    final int clockMs = ref.watch(recordingClockProvider);
    final bool reconnecting = state.reconnecting;
    final List<Speaker> speakers = state.speakers.isEmpty && state.segments.isNotEmpty
        ? deriveSpeakers(state.segments, meetingId: state.meetingId ?? '')
        : state.speakers;
    final List<SpeakerChipView> chips = <SpeakerChipView>[
      for (int i = 0; i < speakers.length; i++)
        SpeakerChipView(ordinal: i + 1, label: speakers[i].name),
    ];
    final List<TranscriptItemView> items = <TranscriptItemView>[
      for (final TranscriptSegment segment in state.segments)
        TranscriptItemView(
          ordinal: speakerViewFor(speakerId: segment.speakerId, speakers: speakers).ordinal,
          speakerLabel: speakerViewFor(speakerId: segment.speakerId, speakers: speakers).name,
          timeLabel: formatClock(segment.startTime),
          text: segment.text,
        ),
    ];

    return RecordingScreen(
      title: '录音中',
      subtitle: '${_modeLabel(state.mode)}模式',
      clock: formatClock(clockMs),
      speakers: chips,
      items: items,
      liveTag: reconnecting ? '转写已暂停' : '自动滚动',
      liveTagPaused: reconnecting,
      dimTitle: reconnecting,
      paused: state.phase == RecorderPhase.paused,
      scrollController: _liveScroll,
      showBackToBottom: chips.length > 4,
      onBackToBottom: () {
        if (_liveScroll.hasClients) {
          _liveScroll.animateTo(
            _liveScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      },
      topOverlay: reconnecting
          ? AppActionToast(
              title: '网络连接中断',
              subtitle: '正在本地缓存音频，恢复后自动续传',
              actionLabel: '重试',
              onAction: () => ref.read(toastProvider.notifier).show(
                    '正在重试连接…',
                    tone: ToastTone.info,
                  ),
            )
          : null,
      onClose: _close,
      onSettings: () => context.go('/profile'),
      onPauseToggle: () => ref.read(recorderProvider.notifier).togglePause(),
      onStop: _stop,
      onBookmark: () => ref.read(recorderProvider.notifier).addBookmark(),
      onTabTap: _onTabTap,
      selectedTab: 0,
    );
  }

  void _onTabTap(int index) {
    switch (index) {
      case 1:
        context.go('/history');
      case 2:
        context.go('/profile');
      default:
        break;
    }
  }

  int _todayMinutes(List<MeetingSummary> list, DateTime now) {
    int totalMs = 0;
    for (final MeetingSummary item in list) {
      if (_isSameDay(item.createdAt, now)) totalMs += item.durationMs;
    }
    return totalMs ~/ 60000;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _modeLabel(RecordingMode mode) => switch (mode) {
        RecordingMode.meeting => '会议',
        RecordingMode.interview => '访谈',
        RecordingMode.inspiration => '灵感',
      };
}
