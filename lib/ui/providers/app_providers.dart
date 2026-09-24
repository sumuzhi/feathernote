/// UI 层 Riverpod providers：后端门面、历史列表、录音时钟、波形、Toast。
///
/// 设计原则：
/// - **UI 只认 `BackendApi`**（进程内门面），引擎 / 存储 / HTTP 形态对页面透明；
/// - 高频更新的东西（录音计时、波形）拆成独立 provider，
///   避免每 250ms 重建整棵页面树（转写列表可能有上千条）。
library;

import 'dart:async';

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
final FutureProvider<BackendBundle> backendBundleProvider = FutureProvider<BackendBundle>(
  (Ref ref) async {
    final AppConfig config = ref.watch(appConfigProvider);
    final BackendBundle bundle = await createBackend(config: config);
    ref.onDispose(() {
      unawaited(bundle.dispose());
    });
    return bundle;
  },
);

/// 后端门面（UI 的唯一入口）。
final FutureProvider<BackendApi> backendProvider = FutureProvider<BackendApi>(
  (Ref ref) async {
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

  /// 展示一条提示。
  void show(
    String text, {
    ToastTone tone = ToastTone.info,
    bool sticky = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (_disposed) return;
    _timer?.cancel();
    _nonce++;
    state = ToastMessage(
      text: text,
      tone: tone,
      sticky: sticky,
      duration: duration,
      nonce: _nonce,
    );
    if (!sticky) {
      _timer = Timer(duration, clear);
    }
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
final NotifierProvider<ToastController, ToastMessage?> toastProvider =
    NotifierProvider<ToastController, ToastMessage?>(ToastController.new);
