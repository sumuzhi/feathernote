/// 纪要页（屏 03 常规 / 屏 11 超长）。
///
/// 长纪要的阅读体验完全落在 [MinutesScreen]/[MinutesCard]：
/// 摘要默认展示、超长时给出「展开全文 · 摘要约 N 字」、分节带「共 N 条」与
/// 「查看全部 N 条」、底部「查看完整转写」是独立入口行。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/transcription_service.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/minutes_screen.dart';
import '../utils/exporter.dart';
import '../utils/formatters.dart';
import '../utils/minutes_outline.dart';
import '../widgets/app_toast.dart';
import '../widgets/minutes_card.dart';

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
  Meeting? _meeting;
  bool _loading = true;
  bool _favorited = false;
  String _streamBuffer = '';
  bool _generating = false;
  String? _error;
  StreamSubscription<String>? _generationSubscription;
  StreamSubscription<TranscriptEvent>? _eventSubscription;
  String? _finalizeError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_generationSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = await ref.read(backendProvider.future);
      // 订阅终稿进度：finalize_status 变 done → 自动刷新；变 failed → 展示可读原因。
      // （历史缺陷：文案承诺「完成后自动刷新」，但页面从未订阅，实际不会刷新。）
      _eventSubscription ??= api.events.listen(
        _onTranscriptEvent,
        onError: (Object error) => logWarn('meeting', '纪要页事件流错误：$error'),
      );
      final Meeting? meeting = await api.getMeeting(widget.meetingId);
      if (!mounted) return;
      setState(() {
        _meeting = meeting;
        _loading = false;
      });
      if (meeting != null && !meeting.hasMinutes) {
        await _generate();
      } else {
        // 已有纪要（含异常兜底）→ 解除首页的生成锁。
        ref.read(generationInProgressProvider.notifier).end(widget.meetingId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  /// 终稿进度事件：只处理本会议的 done / failed。
  void _onTranscriptEvent(TranscriptEvent event) {
    if (event is! FinalizeProgress || event.meetingId != widget.meetingId) return;
    switch (event.status) {
      case 'done':
        unawaited(_onFinalizeDone());
      case 'failed':
        if (!mounted) return;
        setState(() => _finalizeError = event.error ?? '终稿处理失败');
        unawaited(_refresh());
      default:
        break;
    }
  }

  /// 终稿完成：先刷新会议详情（拿到终稿逐字稿），必要时用终稿重生成纪要。
  Future<void> _onFinalizeDone() async {
    final int before = _meeting?.segments.length ?? -1;
    await _refresh();
    final Meeting? after = _meeting;
    if (!mounted || after == null) return;
    final bool transcriptChanged = after.segments.length != before;
    if (transcriptChanged || !after.hasMinutes) {
      await _generate(force: true);
    }
  }

  Future<void> _generate({bool force = false}) async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _streamBuffer = '';
    });
    Object? failure;
    try {
      final api = await ref.read(backendProvider.future);
      _generationSubscription = api
          .generateMinutesStream(widget.meetingId, force: force)
          .listen((String chunk) {
        if (!mounted) return;
        setState(() => _streamBuffer += chunk);
      });
      await _generationSubscription?.asFuture<void>();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    if (failure != null) setState(() => _error = '$failure');
    await _refresh();
    // 生成结束（成功或失败都算结束）→ 解除首页「本会话生成中」锁，
    // 让用户返回首页后可以立刻开始下一段录音。
    ref.read(generationInProgressProvider.notifier).end(widget.meetingId);
    if (!mounted) return;
    setState(() => _generating = false);
  }

  /// 重新拉取会议（纪要与终稿状态都可能已变化），失败不覆盖现有内容。
  Future<void> _refresh() async {
    try {
      final api = await ref.read(backendProvider.future);
      final Meeting? meeting = await api.getMeeting(widget.meetingId);
      if (!mounted) return;
      setState(() => _meeting = meeting ?? _meeting);
    } catch (_) {
      // 刷新失败时保留上一次的快照，不打扰用户。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final Meeting? meeting = _meeting;
    if (meeting == null) {
      return _MissingMeeting(onBack: () => context.go('/history'));
    }

    final Outline bundle = _outlineOf(meeting);
    final String badgeText = meeting.hasMinutes
        ? '已完成'
        : (_generating ? '生成中' : '待生成');

    return MinutesScreen(
      generatedAt: '生成于 ${formatHm(meeting.createdAt)}',
      meetingTitle: meeting.title,
      meetingMeta: '${formatDurationCn(meeting.durationMs)} · '
          '${formatSpeakerCount(meeting.speakerCount)} · '
          '${formatDayTime(meeting.createdAt)}',
      badgeText: badgeText,
      notice: _noticeFor(meeting),
      minutes: bundle.view,
      onClose: () => context.go('/history'),
      onShare: _share,
      onExport: _export,
      onFavorite: () {
        setState(() => _favorited = !_favorited);
        ref.read(toastProvider.notifier).show(
              _favorited ? '已收藏' : '已取消收藏',
              tone: ToastTone.success,
            );
      },
      favorited: _favorited,
    );
  }

  Future<void> _share() async {
    final Meeting? meeting = _meeting;
    if (meeting == null) return;
    await Clipboard.setData(
      ClipboardData(text: '${meeting.title}\n\n${meeting.minutesMd ?? ''}'),
    );
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(
          '纪要已复制，可直接分享',
          tone: ToastTone.success,
          duration: const Duration(milliseconds: 2200),
        );
  }

  Future<void> _export() async {
    final Meeting? meeting = _meeting;
    if (meeting == null) return;
    try {
      final String path = await exportTextFile(
        fileName: meeting.title,
        content: meeting.minutesMd ?? '',
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
            '已导出：$path',
            tone: ToastTone.success,
            duration: const Duration(milliseconds: 2200),
          );
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
            '导出失败：$error',
            tone: ToastTone.warning,
          );
    }
  }

  /// 顶部提示条文案：**与行为一致**（终稿 pending 会自动刷新 → 明说；
  /// failed 展示可读原因，不骗用户）。
  String? _noticeFor(Meeting meeting) {
    switch (meeting.finalizeStatus) {
      case FinalizeStatus.pending:
        return '终稿处理中 · 完成后自动刷新纪要';
      case FinalizeStatus.failed:
        final String reason = meeting.finalizeError ?? _finalizeError ?? '未知原因';
        return '终稿失败：$reason（逐字稿保留实时稿）';
      case FinalizeStatus.done:
      case FinalizeStatus.none:
        return null;
    }
  }

  /// 把 Markdown 纪要解析为界面结构；生成中则流式预览当前缓冲。
  Outline _outlineOf(Meeting meeting) {
    final String raw = _generating && _streamBuffer.isNotEmpty
        ? _streamBuffer
        : (meeting.minutesMd ?? '');
    if (raw.trim().isEmpty) {
      return _generating ? Outline.generating() : Outline.empty(error: _error);
    }
    final MinutesOutline outline = parseMinutesOutline(raw);
    final int chars = outline.summaryChars > 0
        ? outline.summaryChars
        : countChars(outline.raw);
    final bool long = countChars(outline.raw) > 600;

    final List<MinutesSectionView> sections = <MinutesSectionView>[
      for (int i = 0; i < outline.sections.length; i++)
        MinutesSectionView(
          title: outline.sections[i].total > 0
              ? '${outline.sections[i].title} · 共 ${outline.sections[i].total} 条'
              : outline.sections[i].title,
          items: _visibleItems(outline.sections[i].items),
          orangeDots: i == 0,
          moreLabel: outline.sections[i].items.length > _maxItemsPerSection
              ? '查看全部 ${outline.sections[i].total} 条${outline.sections[i].noun}'
              : null,
        ),
    ];

    return Outline(
      view: MinutesView(
        title: '✦ AI 结构化纪要',
        modelTag: meeting.minutesPartial ? '生成中断' : 'qwen3.7-plus',
        longTag: long,
        abstractText: outline.summary.isEmpty
            ? (outline.tailBody.isEmpty ? '纪要生成中…' : outline.tailBody)
            : outline.summary,
        sections: sections,
        transcriptChars: '${formatThousands(meeting.segments.fold<int>(0, (int sum, segment) => sum + countChars(segment.text)))} 字 ›',
        onOpenTranscript: () => context.go('/meeting/${meeting.id}/transcript'),
      ),
      chars: chars,
    );
  }

  static const int _maxItemsPerSection = 3;

  List<String> _visibleItems(List<String> items) => items.length > _maxItemsPerSection
      ? items.sublist(0, _maxItemsPerSection)
      : items;
}

/// 解析结果包装（摘要字符数 + 视图）。
class Outline {
  /// 构造。
  const Outline({required this.view, required this.chars});

  /// 空态。
  factory Outline.empty({String? error}) => Outline(
        view: MinutesView(
          title: '✦ AI 结构化纪要',
          modelTag: '待生成',
          abstractText: error == null ? '纪要尚未生成。' : '纪要生成失败：$error',
          sections: const <MinutesSectionView>[],
          transcriptChars: '0 字 ›',
        ),
        chars: 0,
      );

  /// 生成中。
  factory Outline.generating() => const Outline(
        view: MinutesView(
          title: '✦ AI 结构化纪要',
          modelTag: 'qwen3.7-plus',
          abstractText: '正在根据逐字稿生成结构化纪要，请稍候…',
          sections: <MinutesSectionView>[],
          transcriptChars: '…',
        ),
        chars: 0,
      );

  /// 视图。
  final MinutesView view;

  /// 摘要字符数。
  final int chars;
}

class _MissingMeeting extends StatelessWidget {
  const _MissingMeeting({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('会议不存在或已被删除'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBack, child: const Text('返回历史')),
          ],
        ),
      ),
    );
  }
}
