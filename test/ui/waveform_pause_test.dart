/// 问题 2 回归：**暂停时波形必须冻结**（不再「假装在动」）。
///
/// `Waveform` 的 44 根柱由 `AnimationController.repeat(reverse: true)` 自循环驱动，
/// 与真实音频无关 —— 因此旧实现下暂停后动画仍在跑。现在 `animating: false`
/// 应停止推进并**冻结在当前电平**；恢复后继续。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/widgets/waveform.dart';

/// 各柱当前的纵向缩放（`Matrix4.diagonal3Values(1, scale, 1)` 的 scaleY）。
List<double> _scales(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(of: find.byType(Waveform), matching: find.byType(Transform)),
    )
    .map((Transform t) => t.transform.storage[5])
    .toList(growable: false);

Widget _host(bool animating) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => MediaQuery(
            // 显式关闭「减少动效」，确保测的是暂停冻结而非静态降级。
            data: MediaQuery.of(context).copyWith(disableAnimations: false),
            child: Center(child: Waveform(animating: animating)),
          ),
        ),
      ),
    );

void main() {
  testWidgets('运行时波形在推进；animating=false 后冻结在当前电平', (WidgetTester tester) async {
    await tester.pumpWidget(_host(true));
    await tester.pump(const Duration(milliseconds: 40));
    final List<double> before = _scales(tester);

    await tester.pump(const Duration(milliseconds: 300));
    final List<double> moving = _scales(tester);
    expect(moving, isNot(equals(before)), reason: '运行时波形应在推进');

    // 暂停：不再推进。
    await tester.pumpWidget(_host(false));
    await tester.pump();
    final List<double> frozen = _scales(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final List<double> still = _scales(tester);
    expect(still, equals(frozen), reason: '暂停后必须冻结，不得继续动');

    // 恢复：重新推进。
    await tester.pumpWidget(_host(true));
    await tester.pump();
    final List<double> resumed = _scales(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scales(tester), isNot(equals(resumed)), reason: '恢复后应继续推进');

    expect(tester.takeException(), isNull);
  });
}
