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
import '../../domain/enums.dart';
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
final NotifierProvider<ToastController, ToastMessage?> toastProvider =
    NotifierProvider<ToastController, ToastMessage?>(ToastController.new);

/// 生成锁的兜底上限。
///
/// 纪要 / 终稿正常在数秒到数十秒内结束；超过该时长仍未收到任何「结束」信号
/// （网络挂起、进程异常、会议被外部删除等），强制解锁，**绝不用一个永久标志
/// 把录音永久锁死**。
const Duration kGenerationLockMax = Duration(seconds: 90);

/// 「本会话正在生成纪要 / 终稿」的会议 ID（`null` = 无）。
///
/// 生命周期：
/// - `begin(meetingId)`：首页「结束并生成」拿到 meetingId 后调用（只锁本会话）；
/// - `end(meetingId)`：纪要页的生成流结束 / 失败事件调用（幂等，非本会话忽略）；
/// - **兜底**：监听会议表，被跟踪会议一旦「已有纪要且终稿不再 pending」或已不存在，
///   自动解锁；再加一个 [kGenerationLockMax] 超时兜底。
///
/// 首页据此禁用「开始录音」，避免用户在上一段仍在生成时又开一段。
class SessionGenerationController extends Notifier<String?> {
  Timer? _guard;

  @override
  String? build() {
    ref.onDispose(() {
      _guard?.cancel();
      _guard = null;
    });
    // 兜底：会议表（drift 流）任一变化都会走到这里。
    ref.listen<AsyncValue<List<MeetingSummary>>>(
      meetingsProvider,
      (
        AsyncValue<List<MeetingSummary>>? previous,
        AsyncValue<List<MeetingSummary>> next,
      ) {
        final String? tracked = state;
        if (tracked == null) return;
        final List<MeetingSummary>? list = next.value;
        if (list == null) return;
        MeetingSummary? meeting;
        for (final MeetingSummary item in list) {
          if (item.id == tracked) {
            meeting = item;
            break;
          }
        }
        // 会议已不存在，或已经不再「生成中」→ 解锁。
        if (meeting == null || !_isGenerating(meeting)) {
          end(tracked);
        }
      },
    );
    return null;
  }

  /// 标记「本会话的 [meetingId] 正在生成纪要 / 终稿」。
  void begin(String meetingId) {
    if (meetingId.isEmpty) return;
    if (state != meetingId) state = meetingId;
    _guard?.cancel();
    _guard = Timer(kGenerationLockMax, () => end(meetingId));
  }

  /// 生成结束（幂等）。[meetingId] 不匹配时忽略。
  void end([String? meetingId]) {
    final String? tracked = state;
    if (tracked == null) return;
    if (meetingId != null && meetingId != tracked) return;
    _guard?.cancel();
    _guard = null;
    state = null;
  }

  /// 「仍在生成中」判定：纪要未完成，或终稿仍 pending。
  static bool _isGenerating(MeetingSummary meeting) =>
      !meeting.hasMinutes || meeting.finalizeStatus == FinalizeStatus.pending;
}

/// 生成锁 provider（详见 [SessionGenerationController]）。
final NotifierProvider<SessionGenerationController, String?> generationInProgressProvider =
    NotifierProvider<SessionGenerationController, String?>(
  SessionGenerationController.new,
);
