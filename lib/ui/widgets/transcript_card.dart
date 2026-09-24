/// 实时转写卡（设计稿 02 号屏 / 2:160）与单条片段行。
///
/// 关键约束（对应用户痛点「转写超长」）：
/// - 卡片内部**独立滚动**，不把整页撑长；
/// - 录音中自动滚到最新（`自动滚动` 徽标）；
/// - 片段一律按 `segment_id` upsert，因此这里只做渲染、不做去重。
library;

import 'package:flutter/material.dart';

import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/speaker_view.dart';
import 'app_badge.dart';
import 'speaker_chips.dart';
import 'surface_card.dart';

/// 实时转写卡。
class TranscriptCard extends StatefulWidget {
  /// 构造转写卡。
  const TranscriptCard({
    super.key,
    required this.segments,
    this.speakers = const <Speaker>[],
    this.autoScroll = true,
    this.maxHeight = 340,
    this.title = '实时转写',
    this.emptyHint = '正在聆听，请开始说话…',
  });

  /// 片段（按时间升序）。
  final List<TranscriptSegment> segments;

  /// 说话人表（来自终稿回填或本地推导）。
  final List<Speaker> speakers;

  /// 是否自动滚动到最新。
  final bool autoScroll;

  /// 内部滚动区最大高度。
  final double maxHeight;

  /// 卡片标题。
  final String title;

  /// 空态文案。
  final String emptyHint;

  @override
  State<TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<TranscriptCard> {
  final ScrollController _controller = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.segments.length;
  }

  @override
  void didUpdateWidget(TranscriptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.segments.length != _lastCount) {
      _lastCount = widget.segments.length;
      if (widget.autoScroll) _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_controller.hasClients) return;
      final double target = _controller.position.maxScrollExtent;
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<TranscriptSegment> segments = widget.segments;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.cardSm, AppSpacing.cardSm, AppSpacing.cardSm, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(widget.title, style: AppTextStyles.label),
              ),
              if (widget.autoScroll) const AppBadge(label: '自动滚动'),
            ],
          ),
          const SizedBox(height: AppSpacing.gapSm),
          if (segments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(widget.emptyHint, style: AppTextStyles.meta),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: ListView.builder(
                controller: _controller,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: segments.length,
                itemBuilder: (BuildContext context, int index) {
                  final TranscriptSegment segment = segments[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == segments.length - 1 ? 10 : 14),
                    child: TranscriptTile(
                      segment: segment,
                      speakers: widget.speakers,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条片段行：圆形序号徽标 + 「说话人 N · mm:ss」+ 正文。
class TranscriptTile extends StatelessWidget {
  /// 构造片段行。
  const TranscriptTile({
    super.key,
    required this.segment,
    required this.speakers,
    this.showSpeakerName = true,
  });

  /// 片段。
  final TranscriptSegment segment;

  /// 说话人表。
  final List<Speaker> speakers;

  /// 是否展示说话人名（07 号屏在过滤态下仍展示）。
  final bool showSpeakerName;

  @override
  Widget build(BuildContext context) {
    final SpeakerView view = speakerViewFor(
      speakerId: segment.speakerId,
      speakers: speakers,
      fallbackName: segment.speakerName,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: speakerColor(view.colorIndex),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${view.ordinal}',
            style: AppTextStyles.badge.copyWith(color: Colors.white, fontSize: 11),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showSpeakerName)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          view.name,
                          style: AppTextStyles.metaSmall.copyWith(
                            color: speakerColor(view.colorIndex),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '  ·  ${formatClock(segment.startTime)}',
                        style: AppTextStyles.metaSmall,
                      ),
                    ],
                  ),
                ),
              Text(segment.text, style: AppTextStyles.body),
            ],
          ),
        ),
      ],
    );
  }
}
