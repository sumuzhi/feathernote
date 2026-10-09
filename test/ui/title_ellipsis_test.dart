/// 标题溢出回归（info 卡 / 最近记录卡）。
///
/// 修复：会议纪要上方信息卡与首页「最近记录」卡的标题改为单行省略
/// （`maxLines: 1` + `TextOverflow.ellipsis`），长标题不再换行挤压下方内容区 /
/// 造成同排卡片高度不齐。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/home_idle_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_badge.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/meeting_info_card.dart';

/// 超长标题（唯一，便于 find.text 精确定位）。
const String _longTitle =
    '这是一段非常非常非常非常非常非常非常非常非常非常非常非常非常非常非常长的会议标题用于测试溢出截断行为';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MeetingInfoCard：长标题单行省略，不换行挤压下方', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: MeetingInfoCard(
            title: _longTitle,
            meta: '32 分钟 · 3 位说话人 · 今天 09:12',
            badgeText: '已完成',
            badgeTone: AppBadgeTone.done,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final Text titleWidget = tester.widget<Text>(find.text(_longTitle));
    expect(titleWidget.maxLines, 1, reason: '长标题必须单行省略，不得换行');
    expect(titleWidget.overflow, TextOverflow.ellipsis);
    // 徽标仍正常渲染（改单行不影响右侧徽标）。
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('首页最近记录卡片：长标题单行省略，不换行', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomeIdleScreen(
          heroStatusText: '待机中',
          heroStatusTail: '今日已记录 42 分钟',
          recentItems: <HistoryItemView>[
            const HistoryItemView(
              title: _longTitle,
              description: '描述内容',
              meta: '32 分钟 · 今天 09:12',
            ),
          ],
          onMicTap: () {},
          onViewAll: () {},
          onTabTap: (int i) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final Text titleWidget = tester.widget<Text>(find.text(_longTitle));
    expect(titleWidget.maxLines, 1, reason: '最近记录卡标题必须单行省略，不得换行');
    expect(titleWidget.overflow, TextOverflow.ellipsis);
  });
}
