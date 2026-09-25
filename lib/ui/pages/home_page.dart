/// 首页：待机态（屏 01）与录音态（屏 02 / 06 / 13）同页切换。
///
/// 页面只做「状态 → 视图数据」的翻译，视觉全部交给 `lib/ui/screens/`，
/// 以便「屏幕目录」能用同一套组件渲染 13 个屏。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/log/log.dart';
import '../../domain/meeting.dart';
import '../../domain/recording_mode.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../providers/quote_provider.dart';
import '../providers/recorder_controller.dart';
import '../screens/home_idle_screen.dart';
import '../screens/recording_screen.dart';
import '../utils/formatters.dart';
import '../utils/speaker_view.dart';
import '../widgets/app_toast.dart';
import '../widgets/history_card.dart';
import '../widgets/quote_dialog.dart';
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
  bool _stopping = false;

  @override
  void dispose() {
    _liveScroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    // 上一段仍在生成纪要 / 终稿时不允许再开一段（按钮本身也已禁用，这里兜底）。
    if (ref.read(generationInProgressProvider) != null) return;
    setState(() => _starting = true);
    try {
      await ref.read(recorderProvider.notifier).startRecording();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// 「结束并生成」：按钮就地 loading → 拿到 meetingId 立即跳详情页。
  ///
  /// 纪要 / 终稿在后台继续跑（[RecorderController.stopAndGenerate] 已改为秒级返回），
  /// 因此这里拿到 meetingId 就跳，不做整页遮罩。
  ///
  /// ⚠️ [_stopping] 必须用 try/finally 复位：否则 stopAndGenerate 抛异常
  /// （如收尾链路错误）会让主页 hero 永远显示「正在结束并生成…」并禁录。
  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    String? meetingId;
    Object? failure;
    try {
      meetingId = await ref.read(recorderProvider.notifier).stopAndGenerate();
    } catch (error) {
      failure = error;
    } finally {
      // 无论成功 / 失败都先解除转圈态（跳详情页也由 meetingId 分支处理）。
      if (mounted && meetingId == null) setState(() => _stopping = false);
    }
    if (!mounted) return;
    if (failure != null) {
      logWarn('record', '结束并生成失败：$failure');
      ref.read(toastProvider.notifier).show(
            '结束并生成失败，请到历史页查看',
            tone: ToastTone.warning,
          );
      return;
    }
    if (meetingId != null) {
      // 上锁：从详情页返回首页时，若本会话仍在生成，开始录音保持禁用。
      ref.read(generationInProgressProvider.notifier).begin(meetingId);
      // 压栈式跳转：系统返回键从纪要页原生 pop 回首页。
      unawaited(context.push('/meeting/$meetingId'));
      return;
    }
    // 兜底：理论上录音中必有 meetingId；为空时提示 + 停首页，绝不卡在 loading。
    ref.read(toastProvider.notifier).show(
          '本次录音未生成会议记录，请到历史页查看',
          tone: ToastTone.warning,
        );
    context.go('/history');
  }

  Future<void> _close() async {
    final RecorderUiState state = ref.read(recorderProvider);
    if (!state.isActive) return;
    // 收尾中不允许丢弃：避免与正在落库 / 归档的流程打架。
    if (_stopping || state.phase == RecorderPhase.stopping) return;
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
    // 收尾中也继续显示录音屏（让「结束并生成」按钮原地转圈），
    // 拿到 meetingId 后才跳详情页。
    if (recorder.isActive || recorder.phase == RecorderPhase.stopping) {
      return _buildRecording(context, recorder);
    }
    return _buildIdle(context);
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
          onTap: () => context.push('/meeting/${list[i].id}'),
        ),
    ];
    // App 不区分录音场景：模式选择已移除，recorder 恒为默认模式（会议）。
    //
    // ⚠️ 生成纪要 / 终稿是**异步后台任务**（generationInProgressProvider 仅由
    // 纪要页自身消费以展示进度），**不阻塞首页**：回主页后可直接开始下一段录音，
    // hero 恒为「待机中」，不再出现「上一段正在生成纪要…」的长 loading。
    final bool busy = _starting || _stopping;
    final String? busyHint = _starting
        ? '正在启动录音…'
        : (_stopping ? '正在结束并生成…' : null);
    final String? dailyQuote = ref.watch(dailyQuoteProvider).value;

    return HomeIdleScreen(
      heroStatusText: busy ? '处理中' : '待机中',
      heroStatusTail: '今日已记录 $todayMinutes 分钟',
      dailyQuote: dailyQuote,
      onQuoteTap: dailyQuote == null || dailyQuote.isEmpty
          ? null
          : () async {
              final bool copied = await showQuoteDialog(context, dailyQuote);
              if (!mounted || !copied) return;
              ref.read(toastProvider.notifier).show(
                    '已复制到剪切板',
                    tone: ToastTone.success,
                  );
            },
      recentItems: recent,
      onMicTap: _start,
      onViewAll: () => context.go('/history'),
      onTabTap: _onTabTap,
      selectedTab: 0,
      busy: busy,
      busyHint: busyHint,
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
          segmentId: segment.segmentId,
          startTimeMs: segment.startTime,
          endTimeMs: segment.endTime,
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
      stopping: state.phase == RecorderPhase.stopping,
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
