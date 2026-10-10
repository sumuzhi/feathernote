/// UI 层 Riverpod providers：后端门面、历史列表、录音时钟、波形、Toast。
///
/// 设计原则：
/// - **UI 只认 `BackendApi`**（进程内门面），引擎 / 存储 / HTTP 形态对页面透明；
/// - 高频更新的东西（录音计时、波形）拆成独立 provider，
///   避免每 250ms 重建整棵页面树（转写列表可能有上千条）。
library;

import 'dart:async';

import 'package:flutter/material.dart' show ModalRoute, RouteObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend_api.dart';
import '../../backend/di.dart';
import '../../core/config/app_config.dart';
import '../../domain/meeting.dart';
import '../widgets/app_toast.dart';

/// 冻结配置（「我的」页面展示 / 后端装配入参）。
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (Ref ref) => AppConfig.defaults(),
);

/// 后端装配结果（含降级原因，供 UI 顶部提示）。
///
/// **必须保活**：后端是 App 生命周期单例（引擎 / SQLite / 会话态 sessionStore）。
/// 录音期间首页只显示录音屏、不再订阅历史/健康，若该 provider 因「无监听者」被
/// Riverpod 释放，会触发 `bundle.dispose()` → `sessionStore.clear()` →
/// 停录时反查不到会话 → **落库逐字稿为空**。故显式 keepAlive。
final FutureProvider<BackendBundle> backendBundleProvider = FutureProvider<BackendBundle>(
  (Ref ref) async {
    ref.keepAlive();
    final AppConfig config = ref.watch(appConfigProvider);
    final BackendBundle bundle = await createBackend(config: config);
    ref.onDispose(() {
      unawaited(bundle.dispose());
    });
    return bundle;
  },
);

/// 后端门面（UI 的唯一入口）。同样保活（录音期间无监听者也不得释放）。
final FutureProvider<BackendApi> backendProvider = FutureProvider<BackendApi>(
  (Ref ref) async {
    ref.keepAlive();
    final BackendBundle bundle = await ref.watch(backendBundleProvider.future);
    return bundle.api;
  },
);

/// 历史列表（drift 流：任何写库都会自动刷新）。
final StreamProvider<List<MeetingSummary>> meetingsProvider =
    StreamProvider<List<MeetingSummary>>((Ref ref) async* {
      final BackendApi api = await ref.watch(backendProvider.future);
      yield* api.watchMeetings();
    });

/// 健康检查（「我的」页面展示引擎 / schema 版本 / 会议数量）。
final FutureProvider<HealthStatus> healthProvider = FutureProvider<HealthStatus>(
  (Ref ref) async {
    final BackendApi api = await ref.watch(backendProvider.future);
    return api.health();
  },
);

/// 录音计时（毫秒）：由 `RecorderController` 每 250ms 写入，仅计时文本订阅它。
class RecordingClock extends Notifier<int> {
  @override
  int build() => 0;

  /// 写入当前已录时长。
  void set(int milliseconds) {
    if (state == milliseconds) return;
    state = milliseconds;
  }

  /// 归零。
  void reset() => set(0);
}

/// 录音计时 provider。
final NotifierProvider<RecordingClock, int> recordingClockProvider =
    NotifierProvider<RecordingClock, int>(RecordingClock.new);

/// 波形数据（最近 N 个音量值，0–1）。
class WaveformController extends Notifier<List<double>> {
  /// 保留的历史长度（与 `Waveform.barCount` 默认值一致）。
  static const int capacity = 44;

  @override
  List<double> build() => const <double>[];

  /// 追加一个音量值。
  void push(double level) {
    final double clamped = level.isNaN ? 0 : level.clamp(0.0, 1.0);
    final List<double> next = <double>[...state, clamped];
    if (next.length > capacity) {
      next.removeRange(0, next.length - capacity);
    }
    state = next;
  }

  /// 清空（开始 / 停止录音时调用）。
  void reset() {
    if (state.isEmpty) return;
    state = const <double>[];
  }
}

/// 波形 provider。
final NotifierProvider<WaveformController, List<double>> waveformProvider =
    NotifierProvider<WaveformController, List<double>>(WaveformController.new);

/// 顶部提示（同一时刻只显示一条）。
class ToastController extends Notifier<ToastMessage?> {
  Timer? _timer;
  int _nonce = 0;
  bool _disposed = false;

  @override
  ToastMessage? build() {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    return null;
  }

  /// 展示一条提示（**统一 [kToastDuration]（3 秒）后自动消失**）。
  ///
  /// 刻意**不提供** `duration` / `sticky` 参数：从结构上杜绝任何调用点把提示改成
  /// 常驻或改长 —— 「所有 Toast 一律 3 秒自动消失」这条产品约定不可被绕过。
  /// 需要「更强可见性」的场景（断线 / 引擎错误）改由**页面内持久状态条**承担，
  /// 不靠延长 toast（见 `home_page.dart` 的 `reconnecting` → `topOverlay`）。
  void show(String text, {ToastTone tone = ToastTone.info}) {
    if (_disposed) return;
    _timer?.cancel();
    _nonce++;
    state = ToastMessage(text: text, tone: tone, nonce: _nonce);
    _timer = Timer(kToastDuration, clear);
  }

  /// 清除提示。
  void clear() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || state == null) return;
    state = null;
  }
}

/// 提示 provider。
/// 路由观察者：页面级副作用订阅用（如转写页退出时停止录音回放）。
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// 历史页 UI 状态缓存（切页保留）：筛选下标 / 搜索词 / 滚动位置。
///
/// 用**可变对象**持有（写入不触发重建）；HistoryPage 在状态变更时写回、
/// 进入时恢复——go_router 的 `go()` 会销毁页外页面，此缓存兜住这些状态。
class HistoryUiCache {
  /// 选中的筛选下标（全部/今天/本周/已总结）。
  int filterIndex = 0;

  /// 搜索词。
  String query = '';

  /// 列表滚动位置（px）。
  double scrollOffset = 0;
}

final Provider<HistoryUiCache> historyUiCacheProvider =
    Provider<HistoryUiCache>((Ref ref) => HistoryUiCache());

final NotifierProvider<ToastController, ToastMessage?> toastProvider =
    NotifierProvider<ToastController, ToastMessage?>(ToastController.new);
