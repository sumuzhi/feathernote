import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/app/app.dart';

/// Bug 1 回归：过度滑动（overscroll）果冻效果。
///
/// 根因是 `MaterialApp.router` 未设置 `scrollBehavior`，落到
/// `MaterialScrollBehavior` 默认值 —— Android 12+ 上即拉伸回弹。
void main() {
  group('全局滚动行为（Bug 1 · 过度滑动果冻）', () {
    testWidgets('使用 ClampingScrollPhysics：到边界硬停，不回弹', (WidgetTester tester) async {
      final ScrollBehavior behavior = buildAppScrollBehavior();
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          home: Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(behavior.getScrollPhysics(captured), isA<ClampingScrollPhysics>());
    });

    testWidgets('不产生拉伸 / 辉光过度滑动指示器', (WidgetTester tester) async {
      final ScrollBehavior behavior = buildAppScrollBehavior();
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          home: Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final Widget indicator = behavior.buildOverscrollIndicator(
        captured,
        const SizedBox.shrink(),
        const ScrollableDetails(direction: AxisDirection.down),
      );
      expect(indicator, isNot(isA<StretchingOverscrollIndicator>()));
      expect(indicator, isNot(isA<GlowingOverscrollIndicator>()));
    });

    testWidgets('列表滚到边界位置不越过 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: buildAppScrollBehavior(),
          home: ListView.builder(
            itemCount: 4,
            itemBuilder: (BuildContext context, int index) =>
                SizedBox(height: 200, child: Text('行 $index')),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pump();
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, 0);

      // 反向拖到底也不越界。
      await tester.drag(find.byType(ListView), const Offset(0, -100000));
      await tester.pump();
      expect(
        scrollable.position.pixels,
        scrollable.position.maxScrollExtent,
      );
    });
  });
}
