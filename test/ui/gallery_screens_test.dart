import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/gallery_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';

/// 逐屏冒烟：13 个屏都必须能无异常地构建出来（「13 屏都要可呈现」的机器证据）。
///
/// 注意：波形与加载指示器是**无限循环动画**，因此这里只 `pump` 固定时长，
/// 不用 `pumpAndSettle`（会超时）；结束时显式卸载以释放 Timer / Ticker。
void main() {
  for (final GalleryEntry entry in kGalleryEntries) {
    testWidgets('${entry.id} ${entry.label} 可渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: GalleryScreenHost(
              screenId: entry.id,
              onExit: _noop,
              onOpenScreen: _noopScreen,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      // 每屏都应有状态栏时间（ScreenFrame 统一渲染）。
      expect(find.text('9:41'), findsOneWidget);

      // 卸载：取消录音演示 Timer 与波形 / 指示器的 Ticker。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('s02 逐秒追加转写片段（对齐 HTML 时间轴）', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const GalleryScreenHost(
            screenId: 's02',
            onExit: _noop,
            onOpenScreen: _noopScreen,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('00:0'), findsWidgets);

    // 推进 30 秒：HTML 的时间轴按 4 倍速推进（`parseT(t) <= recSec*4`），
    // 30s*4 = 120s ⇒ 应已追加 00:12 与 01:48 两条。
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      find.textContaining('我先同步上一季度遗留的三个问题', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void _noop() {}

void _noopScreen(String id) {}
