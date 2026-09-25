/// 纪要页（屏 03 常规 / 屏 11 超长）。
///
/// 长纪要的阅读体验完全落在 [MinutesScreen]/[MinutesCard]：
/// 摘要默认展示、超长时给出「展开全文 · 摘要约 N 字」、底部「查看完整转写」
/// 是独立入口行。分节标题与「查看全部 N 条」等文案**不再由本页手动拼接注入**——
/// 这些属于 LLM 输出之外的占位展示，原始模型并不产出此类数据，故仅由
/// 设计预览（gallery/home_idle）的静态数据承载，真实纪要一律如实呈现分节内容。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/transcription_service.dart';
import '../../core/error/app_error.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/minutes_screen.dart';
import '../theme/app_theme.dart';
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
        await _ensureTranscriptThenGenerate();
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

  /// 「生成前置」守卫：**逐字稿落库确认之前绝不生成纪要**。
  ///
  /// 背景：停录收尾（`onStop`）可能仍在后台进行（UI 超时抢跑）。若此刻立即生成，
  /// 会读到 0 段逐字稿 → LLM 产出无源摘要（历史缺陷）。故这里轮询等待：
  /// 直到「逐字稿非空」或「终稿状态已从 none 变化」（= onStop 已完成落库并触发终稿），
  /// 再触发生成；真正为空则明确提示、不生成。
  Future<void> _ensureTranscriptThenGenerate() async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
    while (mounted) {
      final Meeting? m = _meeting;
      if (m == null) return;
      // 逐字稿已落库（非空），或终稿已进入 pending/done/failed（onStop 必经此刻），即可推进。
      if (m.segments.isNotEmpty || m.finalizeStatus != FinalizeStatus.none) break;
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      await _refresh();
    }
    if (!mounted) return;
    final Meeting? m = _meeting;
    if (m == null) return;

    if (m.segments.isNotEmpty) {
      await _generate();
      return;
    }
    // 逐字稿仍为空：
    if (m.finalizeStatus == FinalizeStatus.pending) {
      // 终稿在处理中，完成后 `_onFinalizeDone` 会带终稿逐字稿强制重生成 —— 保持生成锁。
      logInfo('meeting', '逐字稿暂空但终稿处理中，等待终稿完成后再生成 meeting=${widget.meetingId}');
      return;
    }
    // 确实没有逐字稿（全程静音 / 引擎无输出）：明确提示，不再生成无源纪要。
    ref.read(generationInProgressProvider.notifier).end(widget.meetingId);
    if (m.finalizeStatus == FinalizeStatus.failed) {
      setState(() => _finalizeError = m.finalizeError ?? '终稿处理失败');
    }
    ref.read(toastProvider.notifier).show(
          '未获取到逐字稿，暂无法生成纪要',
          tone: ToastTone.warning,
        );
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
    if (failure != null) {
      final String message =
          failure is AppError ? failure.message : '$failure';
      setState(() => _error = message);
      ref.read(toastProvider.notifier).show(
            '纪要生成失败：$message',
            tone: ToastTone.warning,
          );
    }
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
    // 状态切换（loading / 缺失 / 内容）用淡入过渡，避免硬切闪屏。
    // 同一状态内的数据更新（流式纪要）不换 key，因此不会反复闪。
    return AnimatedSwitcher(
      duration: AppDuration.fade,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey<String>(_stateKey),
        child: _buildBody(context),
      ),
    );
  }

  /// 当前展示态（决定 [AnimatedSwitcher] 是否做过渡）。
  String get _stateKey {
    if (_loading) return 'loading';
    if (_meeting == null) return 'missing';
    return 'content';
  }

  Widget _buildBody(BuildContext context) {
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
      // 关闭 = 回到来源页（压栈 pop）；无栈（深链）时兜底回历史。
      onClose: () => context.canPop() ? context.pop() : context.go('/history'),
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
      return _generating
          ? Outline.generating()
          : Outline.empty(
              error: _error,
              onRetry: _error == null ? null : () => _generate(force: true),
            );
    }
    final MinutesOutline outline = parseMinutesOutline(raw);
    final int chars = outline.summaryChars > 0
        ? outline.summaryChars
        : countChars(outline.raw);
    final bool long = countChars(outline.raw) > 600;

    final List<MinutesSectionView> sections = <MinutesSectionView>[
      for (int i = 0; i < outline.sections.length; i++)
        MinutesSectionView(
          title: outline.sections[i].title,
          items: _visibleItems(outline.sections[i].items),
          orangeDots: i == 0,
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
        // 携带已加载的会议对象：转写页首帧即可渲染内容，避免「空态→内容」闪烁。
        // 压栈式跳转：转写页系统返回键原生 pop 回纪要页。
        onOpenTranscript: () =>
            context.push('/meeting/${meeting.id}/transcript', extra: meeting),
        // 生成失败（如空逐字稿 / 网络）时提供「重新生成」入口。
        onRetry: (_error != null && !_generating)
            ? () => _generate(force: true)
            : null,
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
  factory Outline.empty({String? error, VoidCallback? onRetry}) => Outline(
        view: MinutesView(
          title: '✦ AI 结构化纪要',
          modelTag: '待生成',
          abstractText: error == null ? '纪要尚未生成。' : '纪要生成失败：$error',
          sections: const <MinutesSectionView>[],
          transcriptChars: '0 字 ›',
          onRetry: onRetry,
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
