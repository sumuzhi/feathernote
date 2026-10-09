/// 进程保活前台服务（`foregroundServiceType="microphone|dataSync"`）。
///
/// **为什么需要**：Android 14+（API 34）起，麦克风采集必须由 `microphone` 类型的
/// 前台服务托底；否则进程被系统回收 / 切到后台 / 锁屏时，麦克风流会被系统
/// **提前掐断** —— 表现正是「只录了一小会儿就没声了，UI 却还在显示录音中」。
///
/// **2026-10-09 扩展为引用计数保活协调器**：除了录音，**终稿转写（filetrans
/// 上传+轮询，可达数分钟）与纪要 LLM 流式生成同样是后台被杀高发段**——进程
/// 被回收时生成中断落残篇，正是「历史 desc 与最终纪要不一致」的放大器。
/// 三个持有阶段共享同一服务实例（引用计数，任一存活即保持）：
/// - `recording`：录音中 —— `recorder_controller` 的 `start()`/`stop()`（既有 API）；
/// - `finalize/<meetingId>`：终稿转写轮询（`finalize_poller`）；
/// - `minutes/<meetingId>`：纪要生成（`minutes_service`）。
///
/// 设计约束：
/// - 只在 Android 上生效；其它平台与 `flutter test` 一律 no-op，绝不引入依赖；
/// - 所有失败都吞掉并打日志 —— **前台服务起不来绝不能反过来阻断业务**；
/// - 不注册任务回调（不需要额外 isolate），只用通知把服务顶起来；
/// - start/stop/update 全部经内部队列串行化，杜绝「停止与启动交错」把
///   仍有持有者的服务误杀（release→stop 与 acquire 的竞态）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../log/log.dart';

/// 保活前台服务（进程内单例）。
class RecordingForegroundService {
  RecordingForegroundService._();

  /// 单例。
  static final RecordingForegroundService instance = RecordingForegroundService._();

  /// 服务通知 id。
  static const int serviceId = 256;

  bool _initialized = false;
  bool _running = false;
  bool _batteryPrompted = false;
  final Set<String> _holders = <String>{};

  /// 串行化队列：所有服务生命周期操作严格按调用序执行。
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final Future<T> result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// 当前平台是否走前台服务（Android）。
  bool get supported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// 服务是否已启动（供诊断 / 测试断言）。
  bool get isRunning => _running;

  /// 当前持有者集合（供诊断）。
  Set<String> get holders => Set<String>.of(_holders);

  /// 获取保活（幂等；引用计数）。
  ///
  /// 已有服务在跑时仅更新通知文案（如录音结束转入纪要生成）。
  Future<void> acquire(
    String holder, {
    String? notificationTitle,
    String? notificationText,
  }) {
    if (!supported) return Future<void>.value();
    _holders.add(holder);
    return _serialized(() async {
      await _requestIgnoreBatteryOnce();
      if (_running) {
        if (notificationText != null) {
          try {
            await FlutterForegroundTask.updateService(
              notificationTitle: notificationTitle ?? '智能会议纪要',
              notificationText: notificationText,
            );
          } catch (error) {
            logDebug('foreground', '前台服务通知更新失败（忽略）：$error');
          }
        }
        return;
      }
      await _start(
        notificationText: notificationText ?? '后台任务进行中，点击回到应用',
      );
    });
  }

  /// 释放保活（幂等；引用计数）。
  ///
  /// 仅当**最后一个**持有者释放时才真正停止服务。
  Future<void> release(String holder) {
    if (!supported) return Future<void>.value();
    if (!_holders.remove(holder)) return Future<void>.value();
    return _serialized(() async {
      if (_holders.isNotEmpty) {
        logInfo('foreground', '保活仍有其他持有者，保持服务：$_holders');
        return;
      }
      await _stop();
    });
  }

  /// 录音开始（兼容旧 API，等价 `acquire('recording')`）。
  Future<void> start() =>
      acquire('recording', notificationText: '正在录音，点击回到应用');

  /// 录音结束（兼容旧 API，等价 `release('recording')`）。
  ///
  /// 注意：若终稿转写 / 纪要生成仍在持有，服务**不会**停止。
  Future<void> stop() => release('recording');

  /// 电池优化白名单：每会话最多提示一次（用户拒绝也不反复弹）。
  ///
  /// 国产 ROM 的后台强杀主要来自电池优化策略；白名单是「切后台不被杀」
  /// 最有效的非侵入手段。
  Future<void> _requestIgnoreBatteryOnce() async {
    if (_batteryPrompted) return;
    _batteryPrompted = true;
    try {
      final bool ignored = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (ignored) {
        logInfo('foreground', '电池优化白名单：已忽略，无需请求');
        return;
      }
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      logInfo('foreground', '已弹出电池优化白名单请求（拒绝后本会话不再提示）');
    } catch (error) {
      logWarn('foreground', '电池优化白名单请求失败（忽略）：$error');
    }
  }

  Future<void> _start({required String notificationText}) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      if (!_initialized) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'smart_minutes_recording',
            channelName: '录音与纪要处理保活',
            channelDescription: '录音、转写与纪要生成期间保持进程不被系统中断',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
            enableVibration: false,
            playSound: false,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
            allowWakeLock: true,
            allowWifiLock: false,
          ),
        );
        _initialized = true;
      }
      final ServiceRequestResult result =
          await FlutterForegroundTask.startService(
        serviceId: serviceId,
        // microphone：录音采集托底；dataSync：终稿转写上传/轮询与纪要生成
        // 等网络型后台工作托底（Android 15 的 dataSync 6h/24h 配额对分钟级
        // 任务绰绰有余）。
        serviceTypes: const <ForegroundServiceTypes>[
          ForegroundServiceTypes.microphone,
          ForegroundServiceTypes.dataSync,
        ],
        notificationTitle: '智能会议纪要',
        notificationText: notificationText,
      );
      _running = result is ServiceRequestSuccess;
      if (_running) {
        logInfo(
          'foreground',
          '前台服务已启动（type=microphone|dataSync）',
          <String, Object?>{
            'holders': _holders.toList(),
            'elapsedMs': watch.elapsedMilliseconds,
          },
        );
      } else {
        // Android 14+ 未起前台服务时，麦克风流可能被系统提前掐断。
        logWarn(
          'foreground',
          '前台服务启动失败（录音/处理可能被系统中断）',
          <String, Object?>{'result': '$result', 'elapsedMs': watch.elapsedMilliseconds},
        );
      }
    } catch (error) {
      logWarn('foreground', '前台服务启动异常（录音/处理可能被系统中断）：$error');
    }
  }

  Future<void> _stop() async {
    if (!_running) {
      logDebug('foreground', '前台服务：未运行，跳过停止');
      return;
    }
    try {
      await FlutterForegroundTask.stopService();
      logInfo('foreground', '前台服务已停止');
    } catch (error) {
      logWarn('foreground', '前台服务停止异常：$error');
    } finally {
      _running = false;
    }
  }
}
