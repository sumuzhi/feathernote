/// 纪要页（设计稿 11 号屏 + 生成中态 03）。
///
/// 首页「结束并生成」后跳到这里：自动触发流式纪要生成（打字机），
/// 完成后落库并刷新。长纪要的阅读体验交给 [AISummaryCard] 的
/// 「摘要折叠 + 分节查看全部 + 完整转写独立入口」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart';
import '../../backend/services/minutes_service.dart';
import '../../backend/services/transcription_service.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/exporter.dart';
import '../utils/formatters.dart';
import '../utils/minutes_outline.dart';
import '../utils/speaker_view.dart';
import '../widgets/ai_summary_card.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/cta_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/meeting_info_card.dart';

/// 纪要页。
class MeetingPage extends ConsumerStatefulWidget {
  /// 构造纪要页。
  const MeetingPage({super.key, required this.meetingId});

  /// 会议 ID。
  final String meetingId;

  @override
  ConsumerState<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends ConsumerState<MeetingPage> {
  BackendApi? _api;
  Meeting? _meeting;
  List<TranscriptSegment> _segments = const <TranscriptSegment>[];
  List<Speaker> _speakers = const <Speaker>[];
  StreamSubscription<List<TranscriptSegment>>? _segmentSubscription;
  StreamSubscription<TranscriptEvent>? _eventSubscription;
  StreamSubscription<String>? _generationSubscription;
  bool _loading = true;
  bool _generating = false;
  bool _bookmarked = false;
  String _streamBuffer = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_segmentSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_generationSubscription?.cancel());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final BackendApi api = await ref.read(backendProvider.future);
    if (!mounted) return;
    _api = api;
    await _reload();
    _segmentSubscription = api.watchSegments(widget.meetingId).listen(
      (List<TranscriptSegment> segments) {
        if (!mounted) return;
        setState(() {
          _segments = segments;
          if (_speakers.isEmpty && segments.isNotEmpty) {
            _speakers = deriveSpeakers(segments, meetingId: widget.meetingId);
          }
        });
      },
    );
    _eventSubscription = api.events.listen(_onEvent);
    if (mounted && _meeting?.hasMinutes != true) {
      unawaited(_generate());
    }
  }

  Future<void> _reload() async {
    final BackendApi? api = _api;
    if (api == null) return;
    final Meeting? meeting = await api.getMeeting(widget.meetingId);
    if (!mounted) return;
    setState(() {
      _meeting = meeting;
      _loading = false;
      if (meeting != null) {
        _segments = meeting.segments;
        _speakers = meeting.speakers.isNotEmpty
            ? meeting.speakers
            : deriveSpeakers(meeting.segments, meetingId: widget.meetingId);
      }
    });
  }

  void _onEvent(TranscriptEvent event) {
    if (!mounted) return;
    final String? meetingId = switch (event) {
      TranscriptReplace(:final String meetingId) => meetingId,
      SpeakerUpdate(:final String meetingId) => meetingId,
      FinalizeProgress(:final String meetingId) => meetingId,
      MeetingStopped(:final String meetingId) => meetingId,
      TranscriptUpsert(:final String meetingId) => meetingId,
      MeetingStarted(:final String meetingId) => meetingId,
      EngineErrorEvent() => null,
    };
    if (meetingId != widget.meetingId) return;
    unawaited(_reload());
  }

  Future<void> _generate({bool force = false}) async {
    final BackendApi? api = _api;
    if (api == null || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _streamBuffer = '';
    });
    await _generationSubscription?.cancel();
    final Completer<void> done = Completer<void>();
    _generationSubscription = api
        .generateMinutesStream(widget.meetingId, force: force)
        .listen(
          (String delta) {
            if (!mounted) return;
            setState(() => _streamBuffer += delta);
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _generating = false;
                _error = MinutesService.readableError(error);
              });
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () async {
            if (mounted) setState(() => _generating = false);
            if (!done.isCompleted) done.complete();
            await _reload();
          },
          cancelOnError: true,
        );
    await done.future;
  }

  @override
  Widget build(BuildContext context) {
    final Meeting? meeting = _meeting;
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (meeting == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              AppTopBar(
                title: '会议纪要',
                leadingTooltip: '返回',
                onLeading: () => _leave(context),
              ),
              const Expanded(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '会议不存在',
                  description: '它可能已被删除',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final String markdown = _generating
        ? (_streamBuffer.isNotEmpty ? _streamBuffer : (meeting.minutesMd ?? ''))
        : (meeting.minutesMd ?? '');
    final int transcriptChars = countChars(
      _segments.map((TranscriptSegment s) => s.text).join(),
    );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AppTopBar(
              title: '会议纪要',
              subtitle: '生成于 ${formatHm(meeting.createdAt.toLocal())}',
              leadingTooltip: '返回',
              onLeading: () => _leave(context),
              trailingIcon: Icons.ios_share_rounded,
              trailingTooltip: '分享纪要',
              onTrailing: () => unawaited(_share(markdown.isEmpty ? meeting.title : markdown)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.gapLg),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                    child: MeetingInfoCard(
                      title: meeting.title,
                      meta: '${formatDurationCn(meeting.durationMs)} · '
                          '${formatSpeakerCount(meeting.speakerCount)} · '
                          '${formatDayTime(meeting.createdAt.toLocal())}',
                      badgeLabel: _badgeLabel(meeting),
                      badgeTone: meeting.hasMinutes ? BadgeTone.green : BadgeTone.orange,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.gapSm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                    child: AISummaryCard(
                      markdown: markdown,
                      transcriptChars: transcriptChars,
                      generating: _generating,
                      error: _error,
                      modelName: ref.watch(appConfigProvider).llmModel,
                      onRetry: () => unawaited(_generate(force: true)),
                      onOpenTranscript: () => context.push(
                        '/meeting/${widget.meetingId}/transcript',
                      ),
                    ),
                  ),
                  if (meeting.minutesPartial && !_generating)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        AppSpacing.gapSm,
                        AppSpacing.page,
                        0,
                      ),
                      child: Text(
                        '上次生成中断，已保存草稿。点上方「重新生成」可继续。',
                        style: AppTextStyles.metaSmall,
                      ),
                    ),
                  if (_segments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.gapSm),
                      child: EmptyState(
                        icon: Icons.article_outlined,
                        title: '暂无逐字稿',
                        description: '实时转写为空，或终稿仍在生成中',
                      ),
                    ),
                ],
              ),
            ),
            BottomBar(
              child: CtaRow(
                children: <Widget>[
                  Expanded(
                    child: AppPrimaryButton(
                      label: '导出纪要',
                      icon: Icons.file_download_outlined,
                      onPressed: markdown.isEmpty
                          ? null
                          : () => unawaited(_export(meeting.title, markdown)),
                    ),
                  ),
                  AppIconFab(
                    icon: _bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    tooltip: '收藏纪要',
                    onTap: () {
                      setState(() => _bookmarked = !_bookmarked);
                      ref.read(toastProvider.notifier).show(
                        _bookmarked ? '已收藏（仅本机本次会话）' : '已取消收藏',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _badgeLabel(Meeting meeting) {
    if (_generating) return '生成中';
    if (meeting.minutesPartial) return '生成中断';
    if (meeting.hasMinutes) return '已完成';
    return '待生成';
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history');
    }
  }

  Future<void> _share(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ref.read(toastProvider.notifier).show('纪要已复制到剪贴板', tone: ToastTone.success);
  }

  Future<void> _export(String title, String markdown) async {
    try {
      final String path = await exportTextFile(
        fileName: '${sanitizeFileName(title)}-纪要',
        content: markdown,
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('已导出：$path', tone: ToastTone.success);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('导出失败：$error', tone: ToastTone.warning);
    }
  }
}
