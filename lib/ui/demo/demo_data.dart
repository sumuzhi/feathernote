/// 演示数据：与 `docs/design-reference/smart-minutes-app.html` 里的
/// `TRANSCRIPT` / `HIST` / `HIST09` **逐字一致**。
///
/// 仅用于「屏幕目录」评审态（[kDemoTranscript] 等）与真实数据为空时的占位；
/// 真实运行时由 `BackendApi` 提供。
library;

import 'package:flutter/widgets.dart';

import '../widgets/history_card.dart';
import '../widgets/minutes_card.dart';
import '../widgets/transcript_tile.dart';

/// 一条演示转写（HTML `TRANSCRIPT` 的原始结构）。
class DemoTranscriptEntry {
  /// 构造条目。
  const DemoTranscriptEntry({
    required this.speaker,
    required this.time,
    required this.text,
  });

  /// 说话人序号（1-based）。
  final int speaker;

  /// 时间文案。
  final String time;

  /// 正文。
  final String text;

  /// 秒数（供录音页按时间轴逐条追加）。
  int get seconds {
    final List<String> parts = time.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

/// 演示转写条数（与 `TRANSCRIPT` 长度一致）。
const int kDemoTranscriptCount = 7;

/// HTML `TRANSCRIPT`：7 条。
const List<DemoTranscriptEntry> kDemoTranscript = <DemoTranscriptEntry>[
  DemoTranscriptEntry(
    speaker: 1,
    time: '00:12',
    text: '大家下午好，今天我们主要讨论第三季度的产品规划，以及渠道合作的进展。',
  ),
  DemoTranscriptEntry(
    speaker: 2,
    time: '01:48',
    text: '我先同步上一季度遗留的三个问题，其中最关键的是新用户激活率没有达标。',
  ),
  DemoTranscriptEntry(
    speaker: 1,
    time: '03:05',
    text: '激活率这边我让数据团队重新拉了一版口径，新口径下实际完成 82%。',
  ),
  DemoTranscriptEntry(
    speaker: 3,
    time: '07:22',
    text: '那我建议把 Q3 目标从 30% 上调到 35%，前提是渠道合作能在 8 月底落地。',
  ),
  DemoTranscriptEntry(
    speaker: 2,
    time: '09:40',
    text: '这一段已缓存在本地，网络恢复后自动补传并生成纪要。',
  ),
  DemoTranscriptEntry(
    speaker: 1,
    time: '12:15',
    text: '排期我这周内出。另外激活链路的引导页确实太长了，我建议压缩到两步再测一版数据。',
  ),
  DemoTranscriptEntry(
    speaker: 3,
    time: '15:02',
    text: '渠道那边分成比例还在跟法务对，最迟下周三能给结论，如果延后我第一时间同步大家。',
  ),
];

/// 把演示转写转成界面条目。
///
/// - [take]：取前 N 条（默认全部 7 条）；
/// - [pendingLast]：末条设为「待上传」半透明态（s06）；
/// - [highlightIndex]：该下标设为命中高亮态（s12 的第 3 条）。
List<TranscriptItemView> demoTranscriptViews({
  int take = kDemoTranscriptCount,
  bool pendingLast = false,
  int highlightIndex = -1,
  String? expandNote,
}) {
  final int count = take.clamp(0, kDemoTranscript.length);
  return <TranscriptItemView>[
    for (int i = 0; i < count; i++)
      TranscriptItemView(
        ordinal: kDemoTranscript[i].speaker,
        speakerLabel: '说话人 ${kDemoTranscript[i].speaker}',
        timeLabel: pendingLast && i == count - 1 ? '待上传' : kDemoTranscript[i].time,
        text: kDemoTranscript[i].text,
        pending: pendingLast && i == count - 1,
        highlight: i == highlightIndex,
        expandNote: i == highlightIndex ? expandNote : null,
      ),
  ];
}

/// s12 的转写列表：前 5 条，第 3 条为命中高亮并带「展开这段 · 1,860 字」。
List<TranscriptItemView> demoLongTranscriptViews() {
  return <TranscriptItemView>[
    for (int i = 0; i < 5; i++)
      TranscriptItemView(
        ordinal: kDemoTranscript[i].speaker,
        speakerLabel: '说话人 ${kDemoTranscript[i].speaker}',
        timeLabel: kDemoTranscript[i].time,
        text: i == 2
            ? '激活率这边我让数据团队重新拉了一版口径，新口径下实际完成 82%，原来的统计把沉默用户也算进分母了。这里要说明一下口径差异的具体影响：…'
            : kDemoTranscript[i].text,
        highlight: i == 2,
        expandNote: i == 2 ? '展开这段 · 1,860 字' : null,
      ),
  ];
}

/// HTML `HIST`：4 条（s04）。
List<HistoryItemView> demoHistoryViews({
  void Function(int index)? onTap,
  void Function(int index)? onMore,
}) {
  const List<List<String>> rows = <List<String>>[
    <String>[
      'Q3 产品规划评审',
      '明确激活率目标上调至 35%，渠道合作 8 月底前完成落地。',
      '32 分钟 · 今天 09:12 · 3 人',
      'sum',
    ],
    <String>[
      '渠道合作沟通会',
      '敲定分成比例与首批资源位排期，待法务复核。',
      '18 分钟 · 昨天 16:40 · 2 人',
      'sum',
    ],
    <String>[
      '用户访谈 · 激活链路',
      '三位用户反馈引导页过长，建议压缩至两步。',
      '45 分钟 · 09-18 · 2 人',
      'done',
    ],
    <String>[
      '周例会 · 运营同步',
      '确认下周活动排期，素材需在周三前交付。',
      '26 分钟 · 09-12 · 4 人',
      'done',
    ],
  ];
  return <HistoryItemView>[
    for (int i = 0; i < rows.length; i++)
      HistoryItemView(
        title: rows[i][0],
        description: rows[i][1],
        meta: rows[i][2],
        badge: rows[i][3] == 'sum' ? HistoryBadge.summarized : HistoryBadge.done,
        onTap: onTap == null ? null : () => onTap(i),
        onMore: onMore == null ? null : () => onMore(i),
      ),
  ];
}

/// 历史分组（s09）：今天 / 昨天。
class DemoHistoryGroup {
  /// 构造分组。
  const DemoHistoryGroup({required this.day, required this.items});

  /// 分组标题（今天 / 昨天）。
  final String day;

  /// 卡片。
  final List<HistoryItemView> items;
}

/// HTML `HIST09`：今天 2 条 + 昨天 2 条（末条为截断卡）。
List<DemoHistoryGroup> demoLongHistoryGroups({
  void Function(int index)? onTap,
  void Function(int index)? onMore,
}) {
  return <DemoHistoryGroup>[
    DemoHistoryGroup(
      day: '今天',
      items: <HistoryItemView>[
        HistoryItemView(
          title: 'Q3 产品规划评审',
          description: '明确激活率目标上调至 35%，渠道合作 8 月底前完成落地。',
          meta: '32 分钟 · 09:12 · 3 人',
          badge: HistoryBadge.summarized,
          onTap: onTap == null ? null : () => onTap(0),
          onMore: onMore == null ? null : () => onMore(0),
        ),
        HistoryItemView(
          title: '每日站会 · 研发同步',
          description: '接口联调进度过半，测试环境待运维扩容后恢复。',
          meta: '12 分钟 · 08:30 · 5 人',
          badge: HistoryBadge.summarized,
          onTap: onTap == null ? null : () => onTap(1),
          onMore: onMore == null ? null : () => onMore(1),
        ),
      ],
    ),
    DemoHistoryGroup(
      day: '昨天',
      items: <HistoryItemView>[
        HistoryItemView(
          title: '渠道合作沟通会',
          description: '敲定分成比例与首批资源位排期，待法务复核。',
          meta: '18 分钟 · 16:40 · 2 人',
          badge: HistoryBadge.summarized,
          onTap: onTap == null ? null : () => onTap(2),
          onMore: onMore == null ? null : () => onMore(2),
        ),
        HistoryItemView(
          title: '设计评审 · 激活链路改版',
          description: '确认引导页压缩至两步，新增一键跳过入口。',
          meta: '54 分钟 · 14:05 · 4 人',
          badge: HistoryBadge.summarized,
          cut: true,
          dimBadge: true,
          onTap: onTap == null ? null : () => onTap(3),
          onMore: onMore == null ? null : () => onMore(3),
        ),
      ],
    ),
  ];
}

/// 首页「最近记录」的两张卡（s01）。
List<HistoryItemView> demoRecentViews({
  void Function(int index)? onTap,
}) {
  return <HistoryItemView>[
    HistoryItemView(
      title: 'Q3 产品规划评审',
      description: '32 分钟 · 今天 09:12',
      meta: '',
      badge: HistoryBadge.summarized,
      onTap: onTap == null ? null : () => onTap(0),
    ),
    HistoryItemView(
      title: '渠道合作沟通',
      description: '18 分钟 · 昨天 16:40',
      meta: '',
      badge: HistoryBadge.done,
      onTap: onTap == null ? null : () => onTap(1),
    ),
  ];
}

/// s03 的常规纪要（与 HTML `#s03 .sum-card` 文案一致）。
MinutesView demoShortMinutesView({
  VoidCallback? onOpenTranscript,
  ValueChanged<int>? onMore,
}) {
  return MinutesView(
    title: '✦ AI 结构化纪要',
    modelTag: 'qwen3.7-plus',
    abstractText:
        '本次会议围绕 Q3 产品规划展开，核心共识是将新用户激活率标定为 35%，并要求渠道合作在 8 月底前完成落地，运营侧同步给出资源排期。',
    sections: <MinutesSectionView>[
      const MinutesSectionView(
        title: '重要决策',
        items: <String>[
          'Q3 激活率目标从 30% 上调至 35%，采用新统计口径。',
          '渠道合作协议由商务团队在 8 月底前签署完成。',
        ],
        orangeDots: true,
      ),
      const MinutesSectionView(
        title: '讨论要点',
        items: <String>[
          '激活率按新口径重算后实际完成 82%，此前未达标系统计口径问题。',
          '用户访谈反馈引导页过长，是激活链路最主要的流失点。',
          '渠道合作分成比例仍待法务复核，将直接影响 8 月底能否落地。',
        ],
        orangeDots: false,
      ),
    ],
    transcriptChars: '1,860 字 ›',
    onOpenTranscript: onOpenTranscript,
    onMore: onMore,
  );
}

/// s11 的超长纪要：多「内容较长」标签、摘要截断 + 展开入口、分节带「共 N 条」与「查看全部」。
MinutesView demoLongMinutesView({
  bool expanded = false,
  VoidCallback? onExpandAbstract,
  VoidCallback? onOpenTranscript,
  ValueChanged<int>? onMore,
}) {
  const String truncated =
      '本次会议围绕 Q3 产品规划展开，历时 3 小时 12 分钟，共 8 位发言人参与。核心共识是将新用户激活率目标定为 35%，并要求渠道合作在 8 月底前完成落地，运营…';
  const String full =
      '本次会议围绕 Q3 产品规划展开，历时 3 小时 12 分钟，共 8 位发言人参与。核心共识是将新用户激活率目标定为 35%，并要求渠道合作在 8 月底前完成落地，运营侧同步给出资源排期。'
      '会议前半段复盘了上一季度激活率未达标的原因：统计口径把沉默用户计入分母，重算后实际完成 82%；'
      '中段用三份用户访谈佐证了引导页过长是激活链路最主要的流失点，并决定压缩至两步后重测；'
      '后段就渠道合作分成比例展开讨论，法务复核尚未给出结论，将直接影响 8 月底能否落地。'
      '会议最后明确了三项责任人：数据团队本周内给出新口径看板，商务团队推进协议签署，运营团队同步素材排期。';
  return MinutesView(
    title: '✦ AI 结构化纪要',
    modelTag: 'qwen3.7-plus',
    longTag: true,
    abstractText: expanded ? full : truncated,
    expandNote: expanded ? '收起' : '展开全文 · 摘要约 1,240 字',
    sections: <MinutesSectionView>[
      const MinutesSectionView(
        title: '重要决策 · 共 8 条',
        items: <String>[
          'Q3 激活率目标从 30% 上调至 35%，采用新统计口径。',
          '渠道合作协议由商务团队在 8 月底前签署完成。',
        ],
        orangeDots: true,
        moreLabel: '查看全部 8 条决策',
      ),
      const MinutesSectionView(
        title: '讨论要点 · 共 12 条',
        items: <String>[
          '激活率按新口径重算后实际完成 82%，此前未达标系统计口径问题。',
        ],
        orangeDots: false,
        moreLabel: '查看全部 12 条要点',
      ),
      const MinutesSectionView(
        title: '后续跟进',
        items: <String>[
          '用户访谈反馈引导页过长，是激活链路最主要的流失点。',
        ],
        orangeDots: false,
      ),
    ],
    transcriptChars: '1,860 字 ›',
    onExpandAbstract: onExpandAbstract,
    onOpenTranscript: onOpenTranscript,
    onMore: onMore,
  );
}
