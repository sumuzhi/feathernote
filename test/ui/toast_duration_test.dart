/// 产品约定固化：**所有 Toast 一律「显示 3 秒后自动消失」**。
///
/// 背景：历史上有多处调用点在 `show(...)` 上覆盖了时长（5s / 6s / 2.2s），
/// 且有 1 处 `sticky: true`（永不过期）。产品要求统一为 3 秒。
///
/// 为从**结构上**杜绝回归，`ToastController.show()` 已不再暴露 `duration` / `sticky`
/// 参数（调用点无法覆盖），本测试用 `fakeAsync` 固化「3 秒后 toastProvider 回到 null」。
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_toast.dart';

void main() {
  test('kToastDuration 就是 3 秒（唯一时长来源）', () {
    expect(kToastDuration, const Duration(seconds: 3));
  });

  test('show() 出来的 toast 恰好在 3 秒后回到 null', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ToastController controller = container.read(toastProvider.notifier);

      controller.show('已添加书签');
      expect(container.read(toastProvider), isNotNull);
      expect(container.read(toastProvider)!.text, '已添加书签');

      // 差 1ms 到 3 秒：必须还在。
      async.elapse(const Duration(milliseconds: 2999));
      expect(container.read(toastProvider), isNotNull, reason: '未满 3 秒不得提前消失');

      // 越过 3 秒：必须自动消失。
      async.elapse(const Duration(milliseconds: 2));
      expect(container.read(toastProvider), isNull, reason: '满 3 秒必须自动消失');
    });
  });

  test('警示语气（断线 / 引擎错误）同样 3 秒消失，不再常驻', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ToastController controller = container.read(toastProvider.notifier);

      controller.show('网络波动，正在自动重连…', tone: ToastTone.warning);
      expect(container.read(toastProvider)!.tone, ToastTone.warning);

      async.elapse(const Duration(milliseconds: 2999));
      expect(container.read(toastProvider), isNotNull);

      async.elapse(const Duration(milliseconds: 2));
      expect(container.read(toastProvider), isNull, reason: '警示类 toast 也必须 3 秒消失');
    });
  });

  test('再次 show 会重置计时（以最新一条为准，不叠加）', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ToastController controller = container.read(toastProvider.notifier);

      controller.show('A');
      async.elapse(const Duration(seconds: 2));
      controller.show('B');

      // 距 A 已过 4 秒，但 B 才 2 秒 → 仍在（旧计时器已被取消/重置）。
      async.elapse(const Duration(seconds: 2));
      expect(container.read(toastProvider)!.text, 'B');
      expect(container.read(toastProvider), isNotNull, reason: '新 toast 从自身起算 3 秒');

      async.elapse(const Duration(seconds: 1));
      expect(container.read(toastProvider), isNull);
    });
  });

  test('clear() 可立即清除（例如页面跳转时）', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final ToastController controller = container.read(toastProvider.notifier);

      controller.show('稍后自动消失');
      controller.clear();
      expect(container.read(toastProvider), isNull);

      // clear 后旧的计时器不应再触发（不抛异常）。
      async.elapse(const Duration(seconds: 5));
      expect(container.read(toastProvider), isNull);
    });
  });
}
