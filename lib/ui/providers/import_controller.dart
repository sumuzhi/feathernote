/// 导入链路 Riverpod 控制器（设计 §8.3）。
///
/// - [importEventsProvider]：`BackendApi.importEvents` → UI 增量；
/// - [importProcessingProvider]：屏 15 当前会议的四步快照（每次 emit 新实例，
///   规避 Riverpod 3「同一对象实例被 == 过滤」的陷阱）。
///
/// 驱动双保险（设计 §8.1）：事件流给增量，`meetingsProvider`（库）给兜底——
/// 页面在事件丢失时以 `meeting.importStatus` 为准回填步骤态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/backend_api.dart';
import '../../backend/services/import_service.dart';
import 'app_providers.dart';

/// 导入进度事件流（BackendApi 门面的直通投影）。
final StreamProvider<ImportProgressEvent> importEventsProvider =
    StreamProvider<ImportProgressEvent>((Ref ref) async* {
  final BackendApi api = await ref.watch(backendProvider.future);
  yield* api.importEvents;
});

/// 屏 15 的单步视图状态（`idle` / `running` / `done` / `failed` / `cancelled` / `skip`）。
typedef ImportStepStatus = String;

/// 导入处理快照（四步卡渲染的唯一数据源；不可变，每次事件 emit 新实例）。
class ImportProcessingState {
  /// 构造快照。
  const ImportProcessingState({
    required this.meetingId,
    this.stepStatus = const <String, ImportStepStatus>{},
    this.uploadPercent = 0,
    this.detail,
    this.etaMinutes = 0,
  });

  /// 初始快照（进入屏 15 时：步骤 ① 立即 running，其余待事件）。
  factory ImportProcessingState.initial(String meetingId) {
    return ImportProcessingState(
      meetingId: meetingId,
      stepStatus: <String, ImportStepStatus>{
        ImportService.stepUpload: 'running',
      },
    );
  }

  /// 所属会议 ID。
  final String meetingId;

  /// 步骤 → 状态（缺省视为 `idle`）。
  final Map<String, ImportStepStatus> stepStatus;

  /// 上传进度 0..1。
  final double uploadPercent;

  /// 当前提示（软警告 / 取消原因 / 失败原因）。
  final String? detail;

  /// 预计剩余分钟数。
  final int etaMinutes;

  /// 全部四步是否完成。
  bool get allDone =>
      stepStatus[ImportService.stepUpload] == 'done' &&
      stepStatus[ImportService.stepMinutes] == 'done';
}

/// 屏 15 控制器：消费 [importEventsProvider]，维护「最近一次导入」的快照。
class ImportProcessingController extends Notifier<ImportProcessingState?> {
  @override
  ImportProcessingState? build() {
    ref.listen<AsyncValue<ImportProgressEvent>>(importEventsProvider, (
      AsyncValue<ImportProgressEvent>? previous,
      AsyncValue<ImportProgressEvent> next,
    ) {
      final ImportProgressEvent? event = next.value;
      if (event != null) apply(event);
    });
    return null;
  }

  /// 应用一条进度事件（幂等；换会议自动重置）。
  void apply(ImportProgressEvent event) {
    final ImportProcessingState? current = state;
    final ImportProcessingState base =
        (current == null || current.meetingId != event.meetingId)
            ? ImportProcessingState.initial(event.meetingId)
            : current;

    final Map<String, ImportStepStatus> steps = Map<String, ImportStepStatus>.of(base.stepStatus);
    double percent = base.uploadPercent;
    String? detail = event.detail ?? base.detail;
    int eta = event.etaMinutes;

    switch (event.step) {
      case ImportService.stepUpload:
        steps[ImportService.stepUpload] = event.status;
        if (event.status == 'running') {
          percent = event.percent;
          eta = event.etaMinutes;
        }
      case ImportService.stepExtract:
        steps[ImportService.stepExtract] = event.status;
        if (event.status == 'running' && event.detail != null) {
          detail = event.detail;
        }
        eta = event.etaMinutes;
      case ImportService.stepTranscribe:
        steps[ImportService.stepTranscribe] = event.status;
        eta = event.etaMinutes;
      case ImportService.stepMinutes:
        steps[ImportService.stepMinutes] = event.status;
        eta = event.etaMinutes;
      case ImportService.stepDone:
        steps[ImportService.stepUpload] = 'done';
        steps[ImportService.stepExtract] =
            steps[ImportService.stepExtract] ?? 'skip';
        steps[ImportService.stepTranscribe] = 'done';
        steps[ImportService.stepMinutes] = 'done';
        eta = 0;
      default:
        break;
    }
    // 失败 / 取消后不再推进。
    if (event.status == 'cancelled') {
      detail = event.detail ?? '用户取消';
    }
    state = ImportProcessingState(
      meetingId: base.meetingId,
      stepStatus: steps,
      uploadPercent: percent,
      detail: detail,
      etaMinutes: eta,
    );
  }

  /// 进入屏 15 时重置为指定会议（事件与库都还没给出终态前先展示步骤 ① running）。
  void resetFor(String meetingId) {
    final ImportProcessingState? current = state;
    if (current?.meetingId == meetingId) return;
    state = ImportProcessingState.initial(meetingId);
  }
}

/// 屏 15 快照 provider。
final NotifierProvider<ImportProcessingController, ImportProcessingState?>
importProcessingProvider =
    NotifierProvider<ImportProcessingController, ImportProcessingState?>(
  ImportProcessingController.new,
);
