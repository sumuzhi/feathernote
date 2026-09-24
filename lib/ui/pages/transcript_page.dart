/// 完整转写页（设计稿 07 / 12 号屏）。
///
/// **对应用户痛点「转写超长」**：
/// - 顶部 InfoBar 给出总时长 / 说话人数 / 总字数；
/// - 说话人过滤 chips（含「全部」）就地收敛列表；
/// - 列表虚拟化（`ListView.builder`），上千条片段也只渲染可见行；
/// - 右上角进入搜索，按关键词过滤片段。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/exporter.dart';
import '../utils/formatters.dart';
import '../utils/minutes_outline.dart';
import '../utils/speaker_view.dart';
import '../widgets/app_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/cta_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_bar.dart';
import '../widgets/search_field.dart';
import '../widgets/speaker_chips.dart';
import '../widgets/transcript_card.dart';

/// 完整转写页。
class TranscriptPage extends ConsumerStatefulWidget {
  /// 构造转写页。
  const TranscriptPage({super.key, required this.meetingId});

  /// 会议 ID。
  final String meetingId;

  @override
  ConsumerState<TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends ConsumerState<TranscriptPage> {
  final TextEditingController _search = TextEditingController();
  StreamSubscription<List<TranscriptSegment>>? _subscription;
  Meeting? _meeting;
  List<TranscriptSegment> _segments = const <TranscriptSegment>[];
  List<Speaker> _speakers = const <Speaker>[];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  String? _selectedSpeakerId;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final BackendApi api = await ref.read(backendProvider.future);
    final Meeting? meeting = await api.getMeeting(widget.meetingId);
    if (!mounted) return;
    setState(() {
      _meeting = meeting;
      _segments = meeting?.segments ?? const <TranscriptSegment>[];
      _speakers = meeting == null || meeting.speakers.isEmpty
          ? deriveSpeakers(_segments, meetingId: widget.meetingId)
          : meeting.speakers;
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
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Meeting? meeting = _meeting;
    final List<TranscriptSegment> visible = _visibleSegments();
    final int chars = countChars(visible.map((TranscriptSegment s) => s.text).join());
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AppTopBar(
              title: '完整转写',
              subtitle: meeting?.title,
              leadingIcon: Icons.chevron_left_rounded,
              leadingTooltip: '返回',
              onLeading: () => _leave(context),
              trailingIcon: _searching ? Icons.close_rounded : Icons.search_rounded,
              trailingTooltip: _searching ? '退出搜索' : '搜索转写',
              onTrailing: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              }),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (meeting == null)
              const Expanded(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '会议不存在',
                  description: '它可能已被删除',
                ),
              )
            else ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: AppInfoBar(
                  left: formatTranscriptInfo(
                    durationMs: meeting.durationMs,
                    speakerCount: _speakers.length,
                  ),
                  right: formatCharCount(chars),
                ),
              ),
              if (_searching) ...<Widget>[
                const SizedBox(height: AppSpacing.gapSm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  child: AppSearchField(
                    controller: _search,
                    hintText: '搜索转写内容…',
                    onChanged: (String value) => setState(() => _query = value.trim()),
                    onClear: () => setState(() => _query = ''),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.gapSm),
              if (_speakers.isNotEmpty)
                SpeakerChips(
                  speakers: _speakers,
                  showAll: true,
                  selectedId: _selectedSpeakerId,
                  onSelected: (String? id) => setState(() => _selectedSpeakerId = id),
                ),
              const SizedBox(height: AppSpacing.gapSm),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.article_outlined,
                        title: _segments.isEmpty ? '暂无转写内容' : '没有匹配的片段',
                        description: _segments.isEmpty
                            ? '实时转写为空，或终稿仍在生成中'
                            : '换个关键词或切回「全部」说话人',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.page,
                          0,
                          AppSpacing.page,
                          AppSpacing.gapLg,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: AppSpacing.gap),
                        itemBuilder: (BuildContext context, int index) => TranscriptTile(
                          segment: visible[index],
                          speakers: _speakers,
                        ),
                      ),
              ),
              BottomBar(
                child: CtaRow(
                  children: <Widget>[
                    Expanded(
                      child: AppGhostButton(
                        label: '复制全文',
                        icon: Icons.copy_rounded,
                        expanded: true,
                        onPressed: visible.isEmpty
                            ? null
                            : () => unawaited(_copy(visible)),
                      ),
                    ),
                    Expanded(
                      child: AppPrimaryButton(
                        label: '导出 Markdown',
                        icon: Icons.file_download_outlined,
                        onPressed: visible.isEmpty
                            ? null
                            : () => unawaited(_export(meeting.title, visible)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<TranscriptSegment> _visibleSegments() {
    final String query = _query.toLowerCase();
    if (query.isEmpty && _selectedSpeakerId == null) return _segments;
    return _segments.where((TranscriptSegment segment) {
      if (_selectedSpeakerId != null && segment.speakerId != _selectedSpeakerId) {
        return false;
      }
      if (query.isEmpty) return true;
      return segment.text.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history');
    }
  }

  String _plainText(List<TranscriptSegment> segments) {
    final StringBuffer buffer = StringBuffer();
    for (final TranscriptSegment segment in segments) {
      final SpeakerView view = speakerViewFor(
        speakerId: segment.speakerId,
        speakers: _speakers,
        fallbackName: segment.speakerName,
      );
      buffer.writeln('[${formatClock(segment.startTime)}] ${view.name}：${segment.text}');
    }
    return buffer.toString();
  }

  Future<void> _copy(List<TranscriptSegment> segments) async {
    await Clipboard.setData(ClipboardData(text: _plainText(segments)));
    if (!mounted) return;
    ref.read(toastProvider.notifier).show('全文已复制', tone: ToastTone.success);
  }

  Future<void> _export(String title, List<TranscriptSegment> segments) async {
    try {
      final StringBuffer buffer = StringBuffer()
        ..writeln('# $title · 完整转写')
        ..writeln()
        ..writeln(_plainText(segments));
      final String path = await exportTextFile(
        fileName: '${sanitizeFileName(title)}-转写',
        content: buffer.toString(),
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('已导出：$path', tone: ToastTone.success);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('导出失败：$error', tone: ToastTone.warning);
    }
  }
}
