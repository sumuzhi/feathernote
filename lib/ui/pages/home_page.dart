/// 主页面：待机态 / 录音态 **同页切换**（设计稿 01 / 02 / 03 / 06 / 13）。
///
/// 三处刻意设计（对应此前用户痛点）：
/// 1. 待机态用**居中大圆 mic** 开始录音，不是 Web 那条底部操作条；
/// 2. 录音态的操作是 ActionRow 三键（暂停 / 结束并生成 / 书签）；
/// 3. 录音中若引擎报错，顶部弹出**断线重连**提示条（06 号屏）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/di.dart';
import '../../domain/meeting.dart';
import '../../domain/recording_mode.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../providers/recorder_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/placeholders.dart';
import '../utils/speaker_view.dart';
import '../widgets/action_row.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/history_card.dart';
import '../widgets/record_hero_card.dart';
import '../widgets/section_header.dart';
import '../widgets/segmented_control.dart';
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_card.dart';
import '../widgets/waveform.dart';

/// 主页面。
class HomePage extends ConsumerWidget {
  /// 构造主页面。
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecorderUiState recorder = ref.watch(recorderProvider);
    switch (recorder.phase) {
      case RecorderPhase.idle:
        return const _IdleView();
      case RecorderPhase.starting:
      case RecorderPhase.recording:
      case RecorderPhase.paused:
      case RecorderPhase.stopping:
        return _RecordingView(recorder: recorder);
    }
  }
}

// ── 待机态（01 号屏）──

class _IdleView extends ConsumerWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecorderUiState recorder = ref.watch(recorderProvider);
    final DateTime now = DateTime.now();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.gapLg),
        children: <Widget>[
          const _DegradedBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, AppSpacing.gapLg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${greetingFor(now)}，$kUserDisplayName', style: AppTextStyles.meta),
                      const SizedBox(height: 4),
                      const Text('开始记录', style: AppTextStyles.pageTitle),
                    ],
                  ),
                ),
                _AvatarButton(
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: RecordHeroCard(
              statusText: _statusText(ref, now),
              busy: recorder.phase == RecorderPhase.starting,
              mode: recorder.mode,
              onModeChanged: (RecordingMode mode) =>
                  ref.read(recorderProvider.notifier).setMode(mode),
              onStartRecording: () => unawaited(
                ref
                    .read(recorderProvider.notifier)
                    .startRecording(mode: recorder.mode),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          SectionHeader(
            title: '最近记录',
            actionLabel: '查看全部',
            onAction: () => context.go('/history'),
          ),
          const SizedBox(height: AppSpacing.gapSm),
          const _RecentMeetings(),
          if (recorder.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.gap, AppSpacing.page, 0),
              child: Text(
                recorder.error!,
                style: AppTextStyles.meta.copyWith(color: AppColors.recRed),
              ),
            ),
        ],
      ),
    );
  }

  String _statusText(WidgetRef ref, DateTime now) {
    final List<MeetingSummary>? meetings = ref.watch(meetingsProvider).value;
    if (meetings == null) return '待机中';
    int todayMs = 0;
    for (final MeetingSummary meeting in meetings) {
      final DateTime local = meeting.createdAt.toLocal();
      final bool sameDay =
          local.year == now.year && local.month == now.month && local.day == now.day;
      if (sameDay) todayMs += meeting.durationMs;
    }
    if (todayMs <= 0) return '待机中 · 今日尚未记录';
    return '待机中 · 今日已记录 ${todayMs ~/ 60000} 分钟';
  }
}

class _RecentMeetings extends ConsumerWidget {
  const _RecentMeetings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<MeetingSummary>> async = ref.watch(meetingsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (Object error, StackTrace stack) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: Text('读取历史失败：$error', style: AppTextStyles.meta),
      ),
      data: (List<MeetingSummary> meetings) {
        if (meetings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: EmptyState(
              icon: Icons.mic_none_rounded,
              title: '还没有记录',
              description: '点击上面的橙色按钮开始第一次录音',
            ),
          );
        }
        final List<MeetingSummary> recent = meetings.take(2).toList(growable: false);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Column(
            children: <Widget>[
              for (final MeetingSummary meeting in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.gapSm),
                  child: HistoryCard(
                    summary: meeting,
                    onTap: () => context.push('/meeting/${meeting.id}'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '我的',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: AppSpacing.minTap,
          height: AppSpacing.minTap,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            kUserDisplayName.characters.first,
            style: AppTextStyles.label.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── 录音态（02 / 06 / 13 号屏）──

class _RecordingView extends ConsumerWidget {
  const _RecordingView({required this.recorder});

  final RecorderUiState recorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool paused = recorder.phase == RecorderPhase.paused;
    final bool stopping = recorder.phase == RecorderPhase.stopping;
    final List<TranscriptSegment> segments = recorder.segments;
    final List<Speaker> speakers = recorder.speakers.isNotEmpty
        ? recorder.speakers
        : deriveSpeakers(segments, meetingId: recorder.meetingId ?? '');
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          AppTopBar(
            title: '录音中',
            subtitle: '${recorder.mode.label}模式${paused ? ' · 已暂停' : ''}',
            leadingIcon: Icons.close_rounded,
            leadingTooltip: '放弃本次录音',
            onLeading: () => _confirmDiscard(context, ref),
            trailingIcon: Icons.settings_outlined,
            trailingTooltip: '录音设置',
            onTrailing: () => _showModeSheet(context, ref),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.gap),
              children: <Widget>[
                const SizedBox(height: 4),
                _TimerLine(paused: paused),
                const SizedBox(height: AppSpacing.gap),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  child: Waveform(
                    levels: ref.watch(waveformProvider),
                    active: !paused && !stopping,
                  ),
                ),
                const SizedBox(height: AppSpacing.gap),
                if (speakers.isNotEmpty) ...<Widget>[
                  SpeakerChips(speakers: speakers),
                  const SizedBox(height: AppSpacing.gapSm),
                ],
                if (recorder.reconnecting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.gapSm),
                    child: Text(
                      '网络波动，正在自动重连…已录内容已本地缓存',
                      style: AppTextStyles.meta.copyWith(color: AppColors.primaryDeep),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  child: TranscriptCard(
                    segments: segments,
                    speakers: speakers,
                    maxHeight: 300,
                  ),
                ),
                if (recorder.bookmarks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.gapSm, AppSpacing.page, 0),
                    child: Text(
                      '已添加 ${recorder.bookmarks.length} 个书签 · 最近 '
                      '${formatClock(recorder.bookmarks.last)}',
                      style: AppTextStyles.metaSmall,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.gapSm),
            child: ActionRow(
              paused: paused,
              busy: stopping,
              onTogglePause: () => unawaited(ref.read(recorderProvider.notifier).togglePause()),
              onFinish: () => unawaited(_finish(context, ref)),
              onBookmark: () => ref.read(recorderProvider.notifier).addBookmark(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final String? meetingId = await ref.read(recorderProvider.notifier).stopAndGenerate();
    if (!context.mounted || meetingId == null) return;
    unawaited(context.push('/meeting/$meetingId'));
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        title: const Text('放弃本次录音？', style: AppTextStyles.heroTitle),
        content: const Text('已录制的音频与转写会被删除，无法恢复。', style: AppTextStyles.body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('继续录音', style: AppTextStyles.meta.copyWith(color: AppColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('放弃', style: AppTextStyles.meta.copyWith(color: AppColors.recRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(recorderProvider.notifier).discard();
  }

  void _showModeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('录音设置', style: AppTextStyles.itemTitle),
              const SizedBox(height: AppSpacing.gapSm),
              const Text('模式只影响自动命名与展示，转写链路完全一致。', style: AppTextStyles.meta),
              const SizedBox(height: AppSpacing.gap),
              SegmentedControl<RecordingMode>(
                options: const <SegmentOption<RecordingMode>>[
                  SegmentOption<RecordingMode>(value: RecordingMode.meeting, label: '会议'),
                  SegmentOption<RecordingMode>(value: RecordingMode.interview, label: '访谈'),
                  SegmentOption<RecordingMode>(value: RecordingMode.inspiration, label: '灵感'),
                ],
                value: ref.read(recorderProvider).mode,
                onChanged: (RecordingMode mode) {
                  ref.read(recorderProvider.notifier).setMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计时行：红点 + 大号计时（只订阅 `recordingClockProvider`，不重建整页）。
class _TimerLine extends ConsumerWidget {
  const _TimerLine({required this.paused});

  final bool paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int elapsedMs = ref.watch(recordingClockProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: <Widget>[
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: paused ? 0.35 : 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppColors.recRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(formatClock(elapsedMs), style: AppTextStyles.timer),
        ],
      ),
    );
  }
}

/// 降级提示（缺 Key / mock 引擎时，明确告知而不是静默）。
class _DegradedBanner extends ConsumerWidget {
  const _DegradedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackendBundle? bundle = ref.watch(backendBundleProvider).value;
    final String? reason = bundle?.degradedReason;
    if (reason == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.badgeOrangeBg,
          borderRadius: BorderRadius.circular(AppRadius.infoBar),
        ),
        child: Text(
          '当前使用离线示例引擎（Mock）：$reason',
          style: AppTextStyles.metaSmall.copyWith(color: AppColors.badgeOrangeFg),
        ),
      ),
    );
  }
}
