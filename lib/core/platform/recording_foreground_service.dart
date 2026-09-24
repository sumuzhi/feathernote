/// 录音期间的 Android 前台服务（`foregroundServiceType="microphone"`）。
///
/// **为什么需要**：Android 14+（API 34）起，麦克风采集必须由 `microphone` 类型的
/// 前台服务托底；否则进程被系统回收 / 切到后台 / 锁屏时，麦克风流会被系统
/// **提前掐断** —— 表现正是「只录了一小会儿就没声了，UI 却还在显示录音中」。
///
/// 设计约束：
/// - 只在 Android 上生效；其它平台与 `flutter test` 一律 no-op，绝不引入依赖；
/// - 所有失败都吞掉并打日志 —— **前台服务起不来绝不能反过来阻断录音**；
/// - 不注册任务回调（不需要额外 isolate），只用通知把服务顶起来。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../log/log.dart';

/// 录音前台服务（进程内单例）。
class RecordingForegroundService {
  RecordingForegroundService._();

  /// 单例。
  static final RecordingForegroundService instance = RecordingForegroundService._();

  /// 服务通知 id。
  static const int serviceId = 256;

  bool _initialized = false;
  bool _running = false;

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

  /// 启动（幂等）。失败只告警。
  Future<void> start() async {
    if (!supported) {
      logInfo('foreground', '前台服务：当前平台不支持（非 Android），跳过');
      return;
    }
    if (_running) {
      logInfo('foreground', '前台服务：已在运行，跳过重复启动');
      return;
    }
    final Stopwatch watch = Stopwatch()..start();
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      if (!_initialized) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'smart_minutes_recording',
            channelName: '录音中',
            channelDescription: '保持麦克风采集不被系统中断',
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
        serviceTypes: const <ForegroundServiceTypes>[
          ForegroundServiceTypes.microphone,
        ],
        notificationTitle: '智能会议纪要',
        notificationText: '正在录音，点击回到应用',
      );
      _running = result is ServiceRequestSuccess;
      if (_running) {
        logInfo(
          'foreground',
          '前台服务已启动（type=microphone）',
          <String, Object?>{'elapsedMs': watch.elapsedMilliseconds},
        );
      } else {
        // Android 14+ 未起 microphone 型前台服务时，麦克风流可能被系统提前掐断。
        logWarn(
          'foreground',
          '前台服务启动失败（录音可能被系统中断）',
          <String, Object?>{'result': '$result', 'elapsedMs': watch.elapsedMilliseconds},
        );
      }
    } catch (error) {
      logWarn('foreground', '前台服务启动异常（录音可能被系统中断）：$error');
    }
  }

  /// 停止（幂等）。失败只告警。
  Future<void> stop() async {
    if (!supported) return;
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
