/// 回归：Toast 文案**不得**出现「双下划线」。
///
/// 根因（2026-09-26 定位）：Toast 浮层挂在 `MaterialApp.builder` 层，位于
/// Navigator 之外、无任何 [Material] 祖先 —— 此处的 [Text] 会继承
/// MaterialApp 的错误兜底样式 `_errorTextStyle`（`TextDecoration.underline`
/// + `decorationStyle: double` + 黄色装饰色 + `fontFamily: monospace`）。
/// Toast 自己的样式只覆盖颜色 / 字号 / 字重，`decoration` / `fontFamily`
/// 为 null 时原样继承 → 文案下出现黄色双下划线（此前误判为打包字体渲染问题）。
///
/// 修复：`app_toast.dart` 的 `toastTextEnvironment` 包一层 [DefaultTextStyle]
/// 把 `decoration` 归零。本文件在**复现环境**（home 直放、无 Material 祖先）
/// 下锁定该契约：合并后的最终样式 `decoration == TextDecoration.none`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_toast.dart';

Widget _host(Widget child) => MaterialApp(home: child);

/// 取某个 Text 的**最终合并样式**里的 decoration。
TextDecoration? _decorationOf(WidgetTester tester, String text) {
  final Finder richFinder = find
      .byWidgetPredicate(
        (Widget w) =>
            w is RichText && (w.text as TextSpan).toPlainText().contains(text),
      )
      .first;
  final RichText rich = tester.widget<RichText>(richFinder);
  return (rich.text as TextSpan).style?.decoration;
}

void main() {
  testWidgets('AppToast：文案 decoration 必须是 none（复现无 Material 祖先环境）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppToast(
          message: ToastMessage(text: '已保存 3 条会议', tone: ToastTone.success),
        ),
      ),
    );
    expect(
      _decorationOf(tester, '已保存 3 条会议'),
      TextDecoration.none,
      reason: '修复前此处继承 _errorTextStyle 的 double underline（双下划线根因）',
    );
  });

  testWidgets('AppActionToast：主/副文案 decoration 必须是 none', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppActionToast(
          title: '网络连接中断',
          subtitle: '已切到断线重连',
          actionLabel: '重试',
          onAction: _noop,
        ),
      ),
    );
    expect(_decorationOf(tester, '网络连接中断'), TextDecoration.none);
    expect(_decorationOf(tester, '已切到断线重连'), TextDecoration.none);
  });
}

void _noop() {}
