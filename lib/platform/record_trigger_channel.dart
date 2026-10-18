/// 按键触发通道（Dart 侧）。
///
/// 与原生 `RecordTriggerChannel.kt` 的 `feathernote/record_trigger` 通道对接。
///
/// 链路：root 守护进程读 `/dev/input/event0` 判定长按 → `am start`
/// 透明 Activity → 前台服务 → 本通道 `onTrigger` → [RecordTriggerController]
/// 执行录音开始/停止。
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../core/log/log.dart';

/// 触发命令。
enum TriggerCommand {
  /// 切换：空闲→开始，录音中→停止。
  toggle,

  /// 强制开始。
  start,

  /// 强制停止。
  stop;

  /// 从原生字符串解析（未知值回落 [toggle]）。
  static TriggerCommand parse(String? raw) {
    switch (raw) {
      case 'start':
        return TriggerCommand.start;
      case 'stop':
        return TriggerCommand.stop;
      default:
        return TriggerCommand.toggle;
    }
  }
}

/// 按键触发通道封装。
///
/// 职责：
/// - 接收原生投递的触发命令（[commands] 流）；
/// - 接收「UI 已附着」通知（[uiAttachRequests] 流，headless → 有界面切换）；
/// - 向原生同步录音状态（供守护进程决定震动语义）、查询麦克风权限。
class RecordTriggerChannel {
  RecordTriggerChannel._();

  /// 单例（全局唯一通道，避免重复注册）。
  static final RecordTriggerChannel instance = RecordTriggerChannel._();

  static const MethodChannel _channel =
      MethodChannel('feathernote/record_trigger');

  final StreamController<TriggerCommand> _commands =
      StreamController<TriggerCommand>.broadcast();

  final StreamController<void> _uiAttachRequests =
      StreamController<void>.broadcast();

  bool _attached = false;

  /// 原生投递的触发命令流。
  Stream<TriggerCommand> get commands => _commands.stream;

  /// UI 附着请求流（headless 进程被用户打开时触发）。
  Stream<void> get uiAttachRequests => _uiAttachRequests.stream;

  /// 挂接原生回调（幂等）。
  void attach() {
    if (_attached) return;
    _attached = true;
    _channel.setMethodCallHandler(_handle);
    logInfo('trigger', '按键触发通道已挂接');
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onTrigger':
        final String? raw =
            (call.arguments as Map<Object?, Object?>?)?['command'] as String?;
        final TriggerCommand cmd = TriggerCommand.parse(raw);
        logInfo('trigger', '收到触发命令 command=${cmd.name}（原生 raw=$raw）');
        if (!_commands.isClosed) _commands.add(cmd);
        return true;
      case 'onUiAttached':
        logInfo('trigger', '收到 UI 附着通知');
        if (!_uiAttachRequests.isClosed) _uiAttachRequests.add(null);
        return true;
      default:
        return null;
    }
  }

  /// 拉取冷启动时可能错过的命令（原生侧落盘兜底）。
  ///
  /// 场景：长按触发 → 进程冷启动 → 命令在 Dart 就绪前到达并被落盘。
  /// 启动完成后调用本方法补取，避免「第一次长按没反应」。
  Future<TriggerCommand?> consumePending() async {
    try {
      final String? raw =
          await _channel.invokeMethod<String>('consumePending');
      if (raw == null || raw.isEmpty) return null;
      final TriggerCommand cmd = TriggerCommand.parse(raw);
      logInfo('trigger', '补取到冷启动遗留命令 command=${cmd.name}');
      return cmd;
    } catch (error) {
      logWarn('trigger', '拉取遗留命令失败（忽略）：$error');
      return null;
    }
  }

  /// 同步录音状态给原生（root 守护进程据此决定震动语义）。
  ///
  /// `recording` → 守护进程后续长按按「停止」处理（长震动）；
  /// 其他 → 按「开始」处理（双短震动）。
  Future<void> syncState({required bool recording}) async {
    try {
      await _channel.invokeMethod<bool>(
        'syncState',
        <String, Object?>{'state': recording ? 'recording' : 'idle'},
      );
    } catch (error) {
      logWarn('trigger', '同步录音状态失败（忽略）：$error');
    }
  }

  /// 查询麦克风权限。
  ///
  /// 为什么不用 `record` 插件的 `hasPermission()`：它在 `activity == null`
  /// （headless 无界面）时**直接返回 false**，会导致按键触发路径误判为无权限。
  Future<bool> hasRecordPermission() async {
    try {
      final bool? granted =
          await _channel.invokeMethod<bool>('hasRecordPermission');
      return granted ?? false;
    } catch (error) {
      logWarn('trigger', '查询麦克风权限失败（按无权限处理）：$error');
      return false;
    }
  }

  /// 通知原生「UI 已附着」。
  Future<void> notifyUiAttached() async {
    try {
      await _channel.invokeMethod<bool>('uiAttached');
    } catch (_) {
      // 忽略：原生侧不依赖这个确认。
    }
  }
}
