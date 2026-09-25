/// 播放组件的**渲染位置**回归：必须且只能出现在「当前段」那一条上。
///
/// 背景（用户现象）：点其它段落播放时，进度条 + 「已播 / 段长」会出现在
/// **错误的条目**上。两层成因，这里分别固化：
/// 1. 定位只靠 `segmentId` —— 实时 ASR 任务重启后 sentence 编号从 1 重新开始，
///    `seg_1` 会撞车（`SessionStore` 与数据库都以 segmentId 为键）；
/// 2. 列表条目没有稳定 key —— Flutter 按位置复用 Element，过滤/重排后组件会
///    渲染到别的条目上。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';

/// 构造 4 条，其中 [activeIndex] 为当前段；前两条**刻意共用 segmentId**
/// （模拟 ASR 重启后编号撞车），靠 startMs 区分。
List<TranscriptItemView> _items(int activeIndex) => <TranscriptItemView>[
      for (int i = 0; i < 4; i++)
        TranscriptItemView(
          ordinal: (i % 3) + 1,
          speakerLabel: '说话人 ${(i % 3) + 1}',
          timeLabel: '00:0$i',
          text: '第 $i 段正文',
          segmentId: i < 2 ? 'seg_1' : 'seg_${i + 1}',
          startTimeMs: i * 3000,
          endTimeMs: i * 3000 + 10000,
          playActive: i == activeIndex,
          isPlaying: i == activeIndex,
          playProgress: i == activeIndex ? 0.3 : 0,
          playPositionLabel: '00:03',
          playDurationLabel: '00:10',
        ),
    ];

Widget _host(List<TranscriptItemView> items) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            for (final TranscriptItemView item in items)
              TranscriptTile(
                key: ValueKey<String>('${item.segmentId}@${item.startTimeMs}'),
                item: item,
                // 无 onPlay 时条目根本不渲染播放组件（canPlay=false）。
                onPlay: () {},
              ),
          ],
        ),
      ),
    );

/// 找到播放组件的宿主条目。
TranscriptTile _ownerOf(WidgetTester tester) => tester.widget<TranscriptTile>(
      find.ancestor(
        of: find.text('00:03 / 00:10'),
        matching: find.byType(TranscriptTile),
      ),
    );

void main() {
  testWidgets('播放组件只渲染在当前段那一条上（位置正确）', (WidgetTester tester) async {
    final List<TranscriptItemView> items = _items(2);
    await tester.pumpWidget(_host(items));

    expect(find.text('00:03 / 00:10'), findsOneWidget, reason: '同一时刻只能有一个播放组件');

    final List<TranscriptTile> tiles =
        tester.widgetList<TranscriptTile>(find.byType(TranscriptTile)).toList();
    expect(tiles, hasLength(4));
    expect(_ownerOf(tester), same(tiles[2]), reason: '播放组件必须挂在「当前段」对应的条目上');
    expect(_ownerOf(tester).item.text, '第 2 段正文');
  });

  testWidgets('切换当前段：组件整体移动到新条目，旧条目不再残留',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(_items(1)));
    expect(_ownerOf(tester).item.startTimeMs, 3000);

    await tester.pumpWidget(_host(_items(3)));
    await tester.pumpAndSettle();

    expect(find.text('00:03 / 00:10'), findsOneWidget, reason: '切换后仍只能有一个');
    expect(_ownerOf(tester).item.startTimeMs, 9000, reason: '组件应移动到新的当前段');
  });

  testWidgets('segmentId 撞车时只命中正确的一条（同 id 不同起点）',
      (WidgetTester tester) async {
    final List<TranscriptItemView> items = _items(1);
    await tester.pumpWidget(_host(items));

    expect(items[0].segmentId, items[1].segmentId, reason: '前置条件：两条 segmentId 相同');
    expect(items[0].startTimeMs, isNot(items[1].startTimeMs));

    expect(find.text('00:03 / 00:10'), findsOneWidget, reason: '同 id 不同起点只应命中一条');
    expect(_ownerOf(tester).item.startTimeMs, items[1].startTimeMs);
    expect(_ownerOf(tester).item.startTimeMs, isNot(items[0].startTimeMs));
  });
}
