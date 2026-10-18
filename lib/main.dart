/// 应用入口。
///
/// 方案 B：**没有独立进程的 Node 服务**，后端（引擎 / 存储 / 服务）全部
/// 在 Dart 进程内装配，UI 通过 `BackendApi` 门面调用。详见 `docs/ARCHITECTURE.md`。
///
/// 本文件同时承载**两个 Dart 入口**（智能按键息屏静默录音需要）：
///
/// | 入口 | 触发场景 | 行为 |
/// |---|---|---|
/// | [main] | 用户点图标正常启动 | 建容器 + `runApp`（有界面） |
/// | [headlessMain] | 长按智能键、无界面冷启动 | 只建容器 + 起触发控制器，**不** `runApp` |
///
/// 为什么必须分两个入口：无界面时没有 `FlutterView`，`runApp()` 会抛
/// `StateError`。而 isolate 只能执行一次入口函数，所以当进程已因 headless
/// 起来、用户随后又打开 app 时，只能由原生侧发 `onUiAttached` 通知，
/// 由 [_watchUiAttachRequests] 补挂 UI。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_store_plus/media_store_plus.dart';

import 'app/app.dart';
import 'core/log/log.dart';
import 'core/platform/runtime_mode.dart';
import 'platform/record_trigger_channel.dart';
import 'ui/providers/app_providers.dart';
import 'ui/providers/record_trigger_controller.dart';

/// 进程级 Riverpod 容器。
///
/// 为什么不用顶层的 `ProviderScope` 而自己持有容器：headless 模式下没有 widget
/// 树，`ProviderScope` 根本不存在；而按键触发必须在**没有 UI** 的情况下也能
/// 读写 provider。因此容器由本文件手动创建，UI 挂载时用
/// [UncontrolledProviderScope] 复用同一个容器 —— 保证「后台在录」与
/// 「打开 app 看到的状态」是同一份。
ProviderContainer? _container;

/// 当前容器（供 [headlessMain] 之后补挂 UI 使用；未初始化时抛错）。
ProviderContainer get appContainer {
  final ProviderContainer? c = _container;
  if (c == null) {
    throw StateError('appContainer 尚未初始化：请确认 main/headlessMain 已执行');
  }
  return c;
}

/// 按键触发通道单例。
final RecordTriggerChannel triggerChannel = RecordTriggerChannel.instance;

/// 标准入口：用户点图标启动（有界面）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  markUiAttached();

  final ProviderContainer container = _bootstrapContainer();
  _container = container;

  // 先出首帧：MediaStore 初始化是纯平台通道调用，放在 runApp 之后异步完成，
  // 不再阻塞首帧（导出在用户主动操作时才发生，届时初始化早已完成）。
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SmartMinutesApp(),
    ),
  );

  unawaited(_initMediaStore());
  unawaited(_warmUpBackend(container));
  unawaited(_startTriggerController(container));
  _watchUiAttachRequests(container);
}

/// 无界面入口：长按智能键冷启动（**没有** FlutterView）。
///
/// ⚠️ 必须标注 `@pragma('vm:entry-point')`，否则 release 构建下 AOT 编译器
/// 会把「未被任何 Dart 代码引用」的本函数裁掉，原生侧调用时找不到入口。
@pragma('vm:entry-point')
Future<void> headlessMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  markHeadlessMode();
  logInfo('boot', '无界面入口启动（按键触发，不挂 UI）');

  final ProviderContainer container = _bootstrapContainer();
  _container = container;

  // 注意：这里**不能** runApp —— 没有 FlutterView，runApp 会抛 StateError。
  unawaited(_initMediaStore());
  unawaited(_warmUpBackend(container));
  await _startTriggerController(container);

  // ⚠️ 关键：headless 路径**也必须**监听「UI 附着」通知。
  // 场景：长按触发 → headless 启动并录音 → 用户点开 app 想看实时转写。
  // 此时 isolate 已在跑、main() 不会再次执行，只能靠这个监听补挂 runApp。
  // （此前漏了这里 → 录音中打开 app 是黑屏/白屏，界面不渲染。）
  _watchUiAttachRequests(container);
}

/// 创建进程级 Riverpod 容器。
///
/// 只做「创建」这一件事：**不**在此时读任何 provider。原因是在 headless 路径
/// 下，读 provider 可能触发依赖 Activity 的副作用（例如权限弹窗），而此时
/// 进程没有 Activity —— 会抛 ActivityNotAttachedException。
ProviderContainer _bootstrapContainer() => ProviderContainer();

/// 启动按键触发控制器（幂等；热重载或重复调用安全）。
Future<void> _startTriggerController(ProviderContainer container) async {
  try {
    final RecordTriggerController controller = RecordTriggerController(
      container: container,
      channel: triggerChannel,
    );
    await controller.start();
  } catch (error, stack) {
    logWarn('boot', '按键触发控制器启动失败：$error');
    logDebug('boot', '堆栈：$stack');
  }
}

/// 预热后端（提前建连，缩短首次录音的启动耗时）。
Future<void> _warmUpBackend(ProviderContainer container) async {
  try {
    await container.read(backendProvider.future);
    logInfo('boot', '后端预热完成');
  } catch (error) {
    logWarn('boot', '后端预热失败（不阻断启动）：$error');
  }
}

/// 监听原生「UI 已附着」通知：把 headless 进程补挂成有界面。
///
/// 场景：长按触发 → 进程 headless 启动并开始录音 → 用户想看实时转写，
/// 点开了 app。此时 isolate 已在跑，`main()` 不会再次执行，必须在这里补 `runApp`。
void _watchUiAttachRequests(ProviderContainer container) {
  triggerChannel.uiAttachRequests.listen((_) {
    if (isUiAttached) return;
    logInfo('boot', '收到 UI 附着请求，补挂界面');
    _attachUi(container);
  });
}

/// 把容器挂到 widget 树（headless → 有界面 的唯一入口）。
void _attachUi(ProviderContainer container) {
  if (isUiAttached) return;
  markUiAttached();
  try {
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const SmartMinutesApp(),
      ),
    );
    logInfo('boot', '界面已补挂完成');
  } catch (error, stack) {
    logWarn('boot', '补挂界面失败：$error');
    logDebug('boot', '堆栈：$stack');
  }
}

/// 导出位置初始化：默认写公共 Download/SmartMinutes/（MediaStore，10+ 零权限）。
/// 失败不阻塞启动（导出时有兜底回落应用文档目录）。
Future<void> _initMediaStore() async {
  if (!Platform.isAndroid) return;
  try {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = 'SmartMinutes';
  } catch (_) {
    // ignore: 初始化失败时导出回落应用内目录。
  }
}
