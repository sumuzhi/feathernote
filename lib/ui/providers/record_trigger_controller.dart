// ignore_for_file: prefer_initializing_formals
/// 按键触发的录音控制器：把原生「长按 3 秒」事件翻译成录音开始/停止。
///
/// 设计要点：
/// - **与 UI 解耦**：直接持 [ProviderContainer]，因此 headless（无界面）时
///   同样可以驱动录音全链路；
/// - **防抖**：3 秒内重复触发会被忽略（[kDedupeWindow]），避免按键抖动导致
///   开始后立刻被停止；
/// - **忙碌保护**：录音正在 starting / stopping 时忽略新命令，避免并发状态冲突。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log/log.dart';
import '../../core/platform/runtime_mode.dart';
import '../../platform/record_trigger_channel.dart';
import 'app_providers.dart';
import 'recorder_controller.dart';

/// 重复触发的最小间隔（防抖窗口）。
const Duration kDedupeWindow = Duration(seconds: 3);

/// 按键触发的录音控制器。
///
/// 生命周期与进程一致（不是 autoDispose）：按键可能在任意时刻到达，
/// 包括用户从未打开过 app 的冷启动场景。
class RecordTriggerController {
  RecordTriggerController({
    required ProviderContainer container,
    required RecordTriggerChannel channel,
  })  : _container = container,
        _channel = channel;

  final ProviderContainer _container;
  final RecordTriggerChannel _channel;

  StreamSubscription<TriggerCommand>? _commandSub;
  DateTime? _lastTriggerAt;
  bool _busy = false;
  bool _started = false;

  /// 启动监听（幂等）。
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _channel.attach();
    _commandSub = _channel.commands.listen(
      (TriggerCommand cmd) => unawaited(_dispatch(cmd)),
      onError: (Object error) =>
          logWarn('trigger', '触发命令流异常（忽略）：$error'),
    );

    // 冷启动兜底：命令可能在 Dart 就绪前到达，这里补取一次。
    final TriggerCommand? pending = await _channel.consumePending();
    if (pending != null) {
      await _dispatch(pending);
    }

    logInfo('trigger', '按键触发控制器已就绪');
  }

  /// 处理一条命令。
  Future<void> _dispatch(TriggerCommand cmd) async {
    // 防抖：3 秒内只响应一次（长按 3 秒释放时会连续到达 DOWN 重复事件，
    // 原生侧已去重，这里再兜一层）。
    final DateTime now = DateTime.now();
    final DateTime? last = _lastTriggerAt;
    if (last != null && now.difference(last) < kDedupeWindow) {
      logDebug('trigger', '触发过于频繁，忽略本次 command=${cmd.name}');
      return;
    }

    if (_busy) {
      logInfo('trigger', '上一个录音操作仍未完成，忽略本次 command=${cmd.name}');
      return;
    }

    _lastTriggerAt = now;
    _busy = true;
    try {
      await _execute(cmd);
    } finally {
      _busy = false;
    }
  }

  Future<void> _execute(TriggerCommand cmd) async {
    final RecorderController controller =
        _container.read(recorderProvider.notifier);
    final RecorderPhase phase = _container.read(recorderProvider).phase;

    // 解析实际动作：toggle 需按当前相位决定开始还是停止。
    final bool shouldStop;
    switch (cmd) {
      case TriggerCommand.start:
        shouldStop = false;
      case TriggerCommand.stop:
        shouldStop = true;
      case TriggerCommand.toggle:
        shouldStop =
            phase == RecorderPhase.recording || phase == RecorderPhase.paused;
    }

    // 中间态（starting/stopping）下不打断，避免状态竞争。
    if (phase == RecorderPhase.starting || phase == RecorderPhase.stopping) {
      logInfo('trigger', '录音处于中间态 $phase，忽略本次命令');
      return;
    }

    if (shouldStop) {
      if (phase == RecorderPhase.idle) {
        logInfo('trigger', '当前空闲，无需停止');
        return;
      }
      logInfo('trigger', '长按触发 → 停止录音并生成');
      await _channel.syncState(recording: false);
      await controller.stopAndGenerate();
      logInfo('trigger', '停止流程已发起');
      return;
    }

    // 开始录音：先确认权限（headless 下不能走插件默认查询）。
    if (phase != RecorderPhase.idle) {
      logInfo('trigger', '已在录音中（$phase），忽略开始命令');
      return;
    }

    final bool granted = isHeadlessMode
        ? await _channel.hasRecordPermission()
        : await _container.read(micSourceFactoryProvider)().hasPermission();

    if (!granted) {
      logWarn('trigger', '麦克风权限未授予，无法开始录音（请先在 app 内授权）');
      _channel.syncState(recording: false);
      return;
    }

    logInfo('trigger', '长按触发 → 开始录音');
    await controller.startRecording(title: '');
    _channel.syncState(recording: true);
    logInfo('trigger', '开始录音指令已发出');
  }

  /// 释放监听（进程退出时无需显式调用，保留以备测试）。
  Future<void> dispose() async {
    await _commandSub?.cancel();
    _commandSub = null;
    _started = false;
  }
}
