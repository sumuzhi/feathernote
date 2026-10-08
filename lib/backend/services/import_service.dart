/// 导入编排服务：四步状态机（§4 SSOT：上传 → 分离音轨 → 语音转写 → 纪要生成）。
///
/// 与既有链路的关系（设计 §3.1）：
/// - step1/step2 由本服务编排（可见进度、可取消）；
/// - step3 复用 [FinalizePoller.startWithOssUrl]（提交 → 轮询 → 落盘 → 广播零改动）；
/// - step4 复用 [MinutesService.generateStream]（幂等，缓存短路语义沿用）。
///
/// 取消语义（§4.3）：取消 = 本地停止推进 + `import_status='failed'`（原因「用户取消」）；
/// step1 dio CancelToken / step2 平台取消标志 / step3 poller abandon / step4 中断 SSE。
///
/// 恢复语义（§4.4）：`recoverOnStartup()` 三分支——
/// pending/extracting → 标记失败；transcribing（有 taskId）→ 恢复轮询；
/// minutes → 重触发纪要。done/failed/none 不动。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/ids.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../../platform/media_import_channel.dart';
import '../engine/bailian/filetrans.dart';
import '../storage/audio_archive.dart';
import '../storage/meeting_repository.dart';
import 'finalize_poller.dart';
import 'minutes_service.dart';

/// 导入请求（屏 14 预检通过后提交）。
class ImportRequest {
  /// 构造导入请求。
  const ImportRequest({
    required this.srcPath,
    required this.srcName,
    required this.isVideo,
    required this.sizeBytes,
  });

  /// 选中的本地文件路径（file_picker 返回，可能是 cache 路径）。
  final String srcPath;

  /// 原文件名（含扩展名；标题取去扩展名部分）。
  final String srcName;

  /// 是否按视频处理（扩展名白名单判定；最终以 probeMedia 结果为准）。
  final bool isVideo;

  /// 文件字节数（屏 14 `FileStat.size` 预检结果）。
  final int sizeBytes;
}

/// 导入进度事件（[ImportService.events] 的最小单元）。
class ImportProgressEvent {
  /// 构造进度事件。
  const ImportProgressEvent({
    required this.meetingId,
    required this.step,
    required this.status,
    this.percent = 0,
    this.detail,
    this.etaMinutes = 0,
  });

  /// 会议 ID。
  final String meetingId;

  /// 步骤（[ImportService.stepUpload] / [ImportService.stepExtract] /
  /// [ImportService.stepTranscribe] / [ImportService.stepMinutes] / [ImportService.stepDone]）。
  final String step;

  /// 状态（`running` / `done` / `failed` / `cancelled`）。
  final String status;

  /// 进度 0..1（仅上传步有值，其余为 0 → UI 显示不定进度）。
  final double percent;

  /// 附加说明（如「无需分离」「上传分离后的音轨」）。
  final String? detail;

  /// 预计剩余分钟数（§7 ETA 公式）。
  final int etaMinutes;
}

/// 导入编排服务。
class ImportService {
  /// 构造导入服务。
  ///
  /// [sandboxRoot] 注入沙箱根目录（测试用）；缺省用
  /// `<系统临时目录>/smart-minutes-import`。
  ImportService({
    required this.persistence,
    required this.filetrans,
    required this.finalizePoller,
    required this.minutesService,
    required this.archive,
    required this.mediaImport,
    required this.cfg,
    this.sandboxRoot,
  }) {
    // filetrans 提交成功 → 落库 import_task_id（恢复轮询的依据）。
    finalizePoller.onTaskSubmitted = _onTaskSubmitted;
  }

  /// 持久化门面。
  final MeetingRepository persistence;

  /// filetrans 客户端（流式上传）。
  final BailianFiletrans filetrans;

  /// 终稿轮询器（step3 复用）。
  final FinalizePoller finalizePoller;

  /// 纪要服务（step4 复用）。
  final MinutesService minutesService;

  /// 音频归档（产物落库 audioKey）。
  final AudioArchive archive;

  /// 平台通道封装（step2 分离）。
  final MediaImportChannel mediaImport;

  /// 冻结配置。
  final AppConfig cfg;

  /// 沙箱根目录（测试注入；缺省 `<tmp>/smart-minutes-import`）。
  final Directory? sandboxRoot;

  /// 进度事件流（broadcast：UI 订阅 + 日志旁路）。
  Stream<ImportProgressEvent> get events => _events.stream;
  final StreamController<ImportProgressEvent> _events =
      StreamController<ImportProgressEvent>.broadcast();

  /// step1 上传。
  static const String stepUpload = 'upload';

  /// step2 分离音轨。
  static const String stepExtract = 'extract';

  /// step3 语音转写。
  static const String stepTranscribe = 'transcribe';

  /// step4 纪要生成。
  static const String stepMinutes = 'minutes';

  /// 全部完成。
  static const String stepDone = 'done';

  /// 上传取消令牌（meetingId → token）。
  final Map<String, CancelToken> _uploadTokens = <String, CancelToken>{};

  /// 取消标志（meetingId → 已请求取消）。
  final Set<String> _cancelled = <String>{};

  /// 在途任务（meetingId → running）。
  final Set<String> _running = <String>{};

  /// 当前执行步（meetingId → step），失败事件用它定位失败卡。
  final Map<String, String> _currentStep = <String, String>{};

  // ────────────────────────────────────────────────────────────── 对外入口

  /// 开始导入：第二道预检（probeMedia）→ 建 meeting（`import_pending`）→ 后台跑状态机。
  ///
  /// 返回时 meeting 已落库；上传 / 分离 / 转写 / 纪要全部在后台继续。
  Future<Meeting> startImport(ImportRequest req) async {
    final MediaProbeResult probe = await mediaImport.probeMedia(req.srcPath);
    if (!probe.hasAudio) {
      throw const AppError(ErrorCode.engineError, '该视频没有可用的音频轨道', engineCode: 'E_NO_AUDIO_TRACK');
    }
    if (probe.durationMs > cfg.importMaxDurationHours * 3600000) {
      throw AppError(
        ErrorCode.engineError,
        '音频时长超过 ${cfg.importMaxDurationHours} 小时上限',
        engineCode: 'E_DURATION_LIMIT',
      );
    }
    // diarization 软提示（不阻断，§1.2 / §7）。
    final bool diarizationWarn =
        probe.durationMs > cfg.importDiarizationSoftLimitHours * 3600000;

    // 视频判定以 probe 为准（用户选的 .mp4 可能只有音轨 → 按音频直传）。
    final bool isVideo = req.isVideo && probe.isVideoContainer;
    final Meeting meeting = Meeting(
      id: genMeetingId(),
      title: _titleFromName(req.srcName),
      createdAt: DateTime.now().toUtc(),
      durationMs: probe.durationMs,
      sampleRate: 16000,
      speakerCount: 0,
      status: MeetingStatus.stopped,
      source: MeetingSource.imported,
      finalizeStatus: FinalizeStatus.none,
      transcriptSource: TranscriptSource.realtime,
      audioStatus: AudioStatus.none,
      audioBytes: req.sizeBytes,
      minutesPartial: false,
      segments: const <TranscriptSegment>[],
      speakers: const <Speaker>[],
      importStatus: ImportStatus.importPending,
      importMetaJson: jsonEncode(<String, Object?>{
        'srcName': req.srcName,
        'srcPath': req.srcPath,
        'kind': isVideo ? 'video' : 'audio',
        'sizeBytes': req.sizeBytes,
        'durationMs': probe.durationMs,
        'uploaded': false,
      }),
    );
    await persistence.saveMeeting(meeting);
    logInfo(
      'import',
      '导入已受理 meeting=${meeting.id}',
      <String, Object?>{
        'src': req.srcName,
        'kind': isVideo ? 'video' : 'audio',
        'bytes': req.sizeBytes,
        'durationMs': probe.durationMs,
        'diarizationWarn': diarizationWarn,
      },
    );
    _emit(
      meeting.id,
      stepUpload,
      'running',
      percent: 0,
      detail: diarizationWarn ? '时长超过 ${cfg.importDiarizationSoftLimitHours} 小时，说话人分离可能失败或超时' : null,
      etaMinutes: _etaUploadMinutes(req.sizeBytes),
    );
    unawaited(_run(meeting.id));
    return meeting;
  }

  /// 取消导入（幂等；§4.3）。
  ///
  /// 本地停止推进：step1 中断上传 / step2 原生取消 / step3 放弃轮询 / step4 中断纪要。
  /// `import_status=failed('用户取消')` 由 [_run] 的取消检查点统一落盘（单写者）。
  Future<void> cancelImport(String meetingId) async {
    _cancelled.add(meetingId);
    _uploadTokens[meetingId]?.cancel();
    await mediaImport.cancelExtract(meetingId);
    if (finalizePoller.isInflight(meetingId)) {
      await finalizePoller.abandon(meetingId);
    }
    logInfo('import', '导入取消已受理 meeting=$meetingId');
    if (!_running.contains(meetingId)) {
      // _run 已结束（如 done 之后才点取消）：仅清理标志，不改状态。
      _cancelled.remove(meetingId);
    }
  }

  /// 重试失败的导入（仅 `import_status=failed` 时可调；从可续步骤重跑）。
  ///
  /// 断点判定：终稿已完成 → 只补纪要；产物已归档（audioKey 有效）→ 只重上传产物
  /// 后进转写；视频且原文件已上传过 → 跳过 step1 上传直接分离；否则从头跑
  /// （沙箱原文件若仍在则免重选）。
  Future<void> retryImport(String meetingId) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) {
      throw AppError(ErrorCode.notFound, '会议不存在：$meetingId');
    }
    if (meeting.importStatus != ImportStatus.failed) {
      throw const AppError(ErrorCode.badRequest, '仅失败的导入可以重试');
    }
    if (_running.contains(meetingId)) return;
    final Map<String, Object?> meta = _parseMeta(meeting);
    meta['uploaded'] = false;
    await persistence.saveMeeting(
      meeting.copyWith(
        importStatus: ImportStatus.importPending,
        clearImportError: true,
        importMetaJson: jsonEncode(meta),
      ),
    );
    logInfo('import', '导入重试已受理 meeting=$meetingId');
    _emit(meetingId, stepUpload, 'running', percent: 0, detail: '重试');
    unawaited(_run(meetingId));
  }

  /// 启动恢复（`BackendApi.init()` 末尾调用，§4.4）。
  Future<void> recoverOnStartup() async {
    final List<MeetingSummary> all = await persistence.listMeetings();
    for (final MeetingSummary summary in all) {
      if (summary.importStatus == ImportStatus.none ||
          summary.importStatus == ImportStatus.done ||
          summary.importStatus == ImportStatus.failed) {
        continue;
      }
      final Meeting? meeting = await persistence.loadMeeting(summary.id);
      if (meeting == null) continue;
      switch (meeting.importStatus) {
        case ImportStatus.importPending:
        case ImportStatus.extracting:
          // 分支 ①：无断点续传能力 → 标记失败（重试按钮从头跑，免重选）。
          await persistence.saveMeeting(
            meeting.copyWith(
              importStatus: ImportStatus.failed,
              importError: '应用退出导致导入中断',
            ),
          );
          logWarn('import', '恢复：标记中断失败 meeting=${meeting.id}（原 ${meeting.importStatus.value}）');
          _emit(meeting.id, stepUpload, 'failed', detail: '应用退出导致导入中断');
        case ImportStatus.transcribing:
          final String taskId = meeting.importTaskId ?? '';
          if (taskId.isEmpty) {
            await persistence.saveMeeting(
              meeting.copyWith(importStatus: ImportStatus.failed, importError: '应用退出导致导入中断'),
            );
            _emit(meeting.id, stepTranscribe, 'failed', detail: '应用退出导致导入中断');
            break;
          }
          // 分支 ②：恢复轮询（不重新上传不重新提交，taskId 幂等）。
          logInfo('import', '恢复：续轮询转写 meeting=${meeting.id} task=$taskId');
          _emit(meeting.id, stepTranscribe, 'running', detail: '恢复中');
          unawaited(_resumeTranscribing(meeting));
        case ImportStatus.minutes:
          // 分支 ③：重触发纪要（generateStream 幂等）。
          logInfo('import', '恢复：重触发纪要 meeting=${meeting.id}');
          _emit(meeting.id, stepMinutes, 'running', detail: '恢复中');
          unawaited(_resumeMinutes(meeting));
        case ImportStatus.done:
        case ImportStatus.failed:
        case ImportStatus.none:
          break;
      }
    }
  }

  // ────────────────────────────────────────────────────────────── 状态机主体

  /// 四步状态机主体（fire-and-forget；所有状态落盘由本方法单写）。
  Future<void> _run(String meetingId) async {
    if (_running.contains(meetingId)) return;
    _running.add(meetingId);
    _cancelled.remove(meetingId);
    try {
      final Meeting? loaded = await persistence.loadMeeting(meetingId);
      if (loaded == null) {
        throw AppError(ErrorCode.notFound, '会议不存在：$meetingId');
      }
      final Map<String, Object?> meta = _parseMeta(loaded);
      final String srcPath = (meta['srcPath'] as String?) ?? '';
      final String srcName = (meta['srcName'] as String?) ?? '';
      final bool isVideo = (meta['kind'] as String?) == 'video';
      final int sizeBytes = (meta['sizeBytes'] as num?)?.toInt() ?? 0;
      final String ext = p.extension(srcName).toLowerCase();

      // ── 断点判定（retryImport 的「从可续步骤重跑」）──
      if (loaded.finalizeStatus == FinalizeStatus.done) {
        // 只补纪要。
        await _stepMinutes(meetingId);
        return;
      }
      final String? audioKey = loaded.audioKey;
      String? archivedPath;
      if (audioKey != null && audioKey.isNotEmpty) {
        final String path = await archive.pathForKey(audioKey);
        if (File(path).existsSync()) archivedPath = path;
      }
      if (!isVideo && archivedPath != null) {
        // 音频产物已归档：直接重上传 → 转写。
        _currentStep[meetingId] = stepUpload;
        final String ossUrl = await _uploadFile(meetingId, archivedPath, '$meetingId$ext', sizeBytes);
        await _stepTranscribe(meetingId, ossUrl);
        return;
      }
      if (isVideo && archivedPath != null) {
        // m4a 已归档：免分离，重上传 → 转写。
        _currentStep[meetingId] = stepUpload;
        final String ossUrl = await _uploadFile(meetingId, archivedPath, '$meetingId.m4a', sizeBytes);
        await _stepTranscribe(meetingId, ossUrl);
        await _stepMinutes(meetingId);
        return;
      }

      // ── step1：复制到沙箱 + 上传原文件（§4.2 ①；上传进度可见）──
      _checkCancelled(meetingId);
      _currentStep[meetingId] = stepUpload;
      final String sandboxCopy = await _ensureSandboxCopy(meetingId, srcPath, ext);
      await _uploadFile(meetingId, sandboxCopy, '$meetingId$ext', sizeBytes);
      final int totalBytes = sizeBytes > 0 ? sizeBytes : File(sandboxCopy).lengthSync();
      meta['uploaded'] = true;
      meta['sizeBytes'] = totalBytes;
      await _patchMeta(meetingId, meta);

      if (isVideo) {
        // ── step2：分离音轨 → m4a → 归档 → 上传 m4a ──
        await _stepExtract(meetingId, sandboxCopy, totalBytes);
        final Meeting? updated = await persistence.loadMeeting(meetingId);
        final String? key = updated?.audioKey;
        if (key == null || key.isEmpty) {
          throw const AppError(ErrorCode.engineError, '音轨归档丢失', engineCode: 'E_EXTRACT_FAILED');
        }
        final String m4aPath = await archive.pathForKey(key);
        _currentStep[meetingId] = stepUpload;
        // 分离+归档完成即标 done：m4a 二次上传失败不应让「分离音轨」卡停在转圈。
        _emit(meetingId, stepExtract, 'done');
        final String m4aOss = await _uploadFile(meetingId, m4aPath, '$meetingId.m4a', totalBytes);
        await _stepTranscribe(meetingId, m4aOss);
        await _stepMinutes(meetingId);
      } else {
        // ── 音频直传：原文件归档（audioKey = 原文件归档，§4.1）──
        // putFileAs 是移动语义 → 上传改读归档后的本地路径。
        final String key = await archive.putFileAs('$meetingId$ext', sandboxCopy);
        await _patchAudioKey(meetingId, key, totalBytes);
        final String archivedPath = await archive.pathForKey(key);
        final String ossUrl = await _uploadFile(meetingId, archivedPath, '$meetingId$ext', totalBytes);
        _emit(meetingId, stepUpload, 'done');
        await _stepTranscribe(meetingId, ossUrl);
        await _stepMinutes(meetingId);
      }
    } catch (error) {
      await _handleRunError(meetingId, error);
    } finally {
      _running.remove(meetingId);
      _uploadTokens.remove(meetingId);
      _currentStep.remove(meetingId);
    }
  }

  /// step2：分离音轨（视频）。
  Future<void> _stepExtract(String meetingId, String srcPath, int sizeBytes) async {
    _checkCancelled(meetingId);
    _currentStep[meetingId] = stepExtract;
    await _saveStatus(meetingId, ImportStatus.extracting);
    final int durationMs = await _durationOf(meetingId);
    _emit(
      meetingId,
      stepExtract,
      'running',
      detail: '上传分离后的音轨',
      etaMinutes: _etaExtractMinutes(durationMs) + _etaUploadMinutes(sizeBytes),
    );
    final Directory root = await _ensureSandboxRoot();
    final String destPath = p.join(root.path, '$meetingId.m4a');
    final MediaExtractResult result = await mediaImport.extractAudioTrack(meetingId, srcPath, destPath);
    // 归档 m4a（audioKey = <meetingId>.m4a，§4.1）。
    final String key = await archive.putFileAs('$meetingId.m4a', result.path);
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting != null) {
      await persistence.saveMeeting(
        meeting.copyWith(
          audioKey: key,
          audioStatus: AudioStatus.done,
          audioBytes: result.bytesWritten,
          durationMs: result.durationMs > 0 ? result.durationMs : meeting.durationMs,
        ),
      );
    }
    logInfo(
      'import',
      '音轨分离完成 meeting=$meetingId',
      <String, Object?>{'bytes': result.bytesWritten, 'durationMs': result.durationMs},
    );
  }

  /// step3：转写（复用 FinalizePoller，oss:// 直通；等待终态落盘）。
  Future<void> _stepTranscribe(String meetingId, String ossUrl) async {
    _checkCancelled(meetingId);
    _currentStep[meetingId] = stepTranscribe;
    await _saveStatus(meetingId, ImportStatus.transcribing);
    final int durationMs = await _durationOf(meetingId);
    _emit(meetingId, stepTranscribe, 'running', etaMinutes: _etaTranscribeMinutes(durationMs));
    await finalizePoller.startWithOssUrl(meetingId, ossUrl: ossUrl, diarization: true);
    await _waitForFinalize(meetingId);
  }

  /// step4：纪要生成（复用 MinutesService.generateStream，幂等）。
  Future<void> _stepMinutes(String meetingId) async {
    _checkCancelled(meetingId);
    _currentStep[meetingId] = stepMinutes;
    await _saveStatus(meetingId, ImportStatus.minutes);
    _emit(meetingId, stepMinutes, 'running', etaMinutes: _etaMinutesStep());
    await for (final String _ in minutesService.generateStream(meetingId)) {
      // 只消费流驱动落盘（MinutesService 内部按结局写库）；取消检查点在每次 delta。
      _checkCancelled(meetingId);
    }
    await _saveStatus(meetingId, ImportStatus.done, clearImportError: true);
    _emit(meetingId, stepDone, 'done', percent: 1);
    logInfo('import', '导入完成 meeting=$meetingId（四步全部就绪）');
  }

  /// 恢复路径 ②：App 被杀后从 importTaskId 续轮询（不重传不重提交）。
  Future<void> _resumeTranscribing(Meeting meeting) async {
    final String meetingId = meeting.id;
    if (_running.contains(meetingId)) return;
    _running.add(meetingId);
    try {
      await finalizePoller.resumeWithTaskId(meetingId, taskId: meeting.importTaskId ?? '');
      await _waitForFinalize(meetingId);
      await _stepMinutes(meetingId);
    } catch (error) {
      await _handleRunError(meetingId, error);
    } finally {
      _running.remove(meetingId);
      _currentStep.remove(meetingId);
    }
  }

  /// 恢复路径 ③：App 被杀后重触发纪要。
  Future<void> _resumeMinutes(Meeting meeting) async {
    final String meetingId = meeting.id;
    if (_running.contains(meetingId)) return;
    _running.add(meetingId);
    try {
      await _stepMinutes(meetingId);
    } catch (error) {
      await _handleRunError(meetingId, error);
    } finally {
      _running.remove(meetingId);
      _currentStep.remove(meetingId);
    }
  }

  /// 等待 FinalizePoller 终态（轮询 taskOf 快照；取消检查点内置）。
  Future<void> _waitForFinalize(String meetingId) async {
    while (true) {
      if (_cancelled.contains(meetingId)) {
        await finalizePoller.abandon(meetingId);
        _checkCancelled(meetingId); // 抛 E_CANCELLED
      }
      final FinalizeTask? task = finalizePoller.taskOf(meetingId);
      if (task?.status == 'done') return;
      if (task?.status == 'failed') {
        throw AppError(ErrorCode.engineError, task?.error ?? '转写失败');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 统一失败处理：cancelled → 「用户取消」；否则「步骤名 + 原因」。
  Future<void> _handleRunError(String meetingId, Object error) async {
    if (_cancelled.contains(meetingId) || (error is AppError && error.engineCode == 'E_CANCELLED')) {
      final Meeting? meeting = await persistence.loadMeeting(meetingId);
      if (meeting != null) {
        await persistence.saveMeeting(
          meeting.copyWith(importStatus: ImportStatus.failed, importError: '用户取消'),
        );
      }
      _cancelled.remove(meetingId);
      logWarn('import', '导入已取消 meeting=$meetingId');
      _emit(meetingId, stepTranscribe, 'cancelled', detail: '用户取消');
      return;
    }
    final String message = _readable(error);
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting != null) {
      await persistence.saveMeeting(
        meeting.copyWith(importStatus: ImportStatus.failed, importError: message),
      );
    }
    logWarn('import', '导入失败 meeting=$meetingId：$message');
    // 失败事件发给**实际失败的那一步**（屏 15 据此把失败落在正确的卡上）。
    _emit(meetingId, _currentStep[meetingId] ?? stepUpload, 'failed', detail: message);
  }

  /// 把底层异常翻译为可读文案（ DioException 裸抛会泄漏实现细节，§6.4 文案表）。
  String _readable(Object error) {
    if (error is AppError) return error.message;
    if (error is DioException) {
      final int? status = error.response?.statusCode;
      if (error.type == DioExceptionType.cancel) return '用户取消';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '网络超时，请检查网络后重试';
      }
      if (status == 401 || status == 403) return '鉴权失败（$status），请检查 API Key 配置';
      if (status == 429) return '请求过于频繁，请稍后重试';
      if (status == 413) return '文件过大，服务端拒绝接收';
      if (status != null && status >= 500) return '服务端异常（$status），请稍后重试';
      return '网络异常，请检查网络后重试';
    }
    return error.toString();
  }

  // ────────────────────────────────────────────────────────────── 工具方法

  /// 流式上传（进度 → 事件流；取消令牌注册）。
  Future<String> _uploadFile(
    String meetingId,
    String filePath,
    String ossName,
    int sizeBytes,
  ) async {
    _checkCancelled(meetingId);
    final CancelToken token = CancelToken();
    _uploadTokens[meetingId] = token;
    try {
      return await filetrans.uploadLocalFileStream(
        filePath,
        filename: ossName,
        cancelToken: token,
        onProgress: (int sent, int total) {
          final int totalBytes = total > 0 ? total : sizeBytes;
          final double percent = totalBytes > 0 ? (sent / totalBytes).clamp(0.0, 1.0).toDouble() : 0;
          _emit(
            meetingId,
            stepUpload,
            'running',
            percent: percent,
            etaMinutes: _etaUploadMinutes(totalBytes - sent),
          );
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const AppError(ErrorCode.engineError, '用户取消', engineCode: 'E_CANCELLED');
      }
      rethrow;
    } finally {
      if (_uploadTokens[meetingId] == token) _uploadTokens.remove(meetingId);
    }
  }

  /// 确保沙箱副本存在（file_picker 的 cache 路径可能被系统清理，§4.2 ①）。
  Future<String> _ensureSandboxCopy(String meetingId, String srcPath, String ext) async {
    final Directory root = await _ensureSandboxRoot();
    final File target = File(p.join(root.path, '$meetingId$ext'));
    if (target.existsSync()) return target.path; // 重试免重选
    if (srcPath.isEmpty) {
      throw const AppError(
        ErrorCode.engineError,
        '原文件已不存在，请重新选择文件',
        engineCode: 'E_SRC_UNREADABLE',
      );
    }
    try {
      await File(srcPath).copy(target.path);
    } catch (_) {
      throw const AppError(
        ErrorCode.engineError,
        '文件读取失败，可能已被移动或删除，请重新选择文件',
        engineCode: 'E_SRC_UNREADABLE',
      );
    }
    logInfo('import', '原文件已复制到沙箱 meeting=$meetingId');
    return target.path;
  }

  Future<Directory> _ensureSandboxRoot() async {
    final Directory? overrideDir = sandboxRoot;
    if (overrideDir != null) {
      if (!overrideDir.existsSync()) overrideDir.createSync(recursive: true);
      return overrideDir;
    }
    final Directory tmp = await getTemporaryDirectory();
    final Directory root = Directory(p.join(tmp.path, 'smart-minutes-import'));
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  /// filetrans 提交成功 → 落库 import_task_id（恢复轮询依据）。
  Future<void> _onTaskSubmitted(String meetingId, String taskId) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    await persistence.saveMeeting(meeting.copyWith(importTaskId: taskId));
    logInfo('import', 'filetrans 任务已登记 meeting=$meetingId task=$taskId');
  }

  /// 只更新 import_status（可清 import_error）。
  Future<void> _saveStatus(String meetingId, ImportStatus status, {bool clearImportError = false}) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    await persistence.saveMeeting(
      meeting.copyWith(importStatus: status, clearImportError: clearImportError),
    );
  }

  /// 只更新 audio_key / audio_bytes（step2 归档后）。
  Future<void> _patchAudioKey(String meetingId, String key, int bytes) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    if (meeting == null) return;
    await persistence.saveMeeting(
      meeting.copyWith(audioKey: key, audioStatus: AudioStatus.done, audioBytes: bytes),
    );
  }

  /// 重写 importMetaJson（断点标记 uploaded 等；总是重新读库避免用过期副本覆盖）。
  Future<void> _patchMeta(String meetingId, Map<String, Object?> meta) async {
    final Meeting? current = await persistence.loadMeeting(meetingId);
    if (current == null) return;
    await persistence.saveMeeting(current.copyWith(importMetaJson: jsonEncode(meta)));
  }

  /// 解析 importMetaJson（损坏时返回空 map，不抛错）。
  Map<String, Object?> _parseMeta(Meeting meeting) {
    final String? raw = meeting.importMetaJson;
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // 忽略：meta 损坏按无 meta 处理。
    }
    return <String, Object?>{};
  }

  /// 当前时长（库中 durationMs，供 ETA）。
  Future<int> _durationOf(String meetingId) async {
    final Meeting? meeting = await persistence.loadMeeting(meetingId);
    return meeting?.durationMs ?? 0;
  }

  /// 标题 = 文件名去扩展名（§2 决策 5）。
  String _titleFromName(String srcName) {
    final String base = p.basenameWithoutExtension(srcName).trim();
    return base.isEmpty ? '导入的会议' : base;
  }

  void _checkCancelled(String meetingId) {
    if (_cancelled.contains(meetingId)) {
      throw const AppError(ErrorCode.engineError, '用户取消', engineCode: 'E_CANCELLED');
    }
  }

  void _emit(String meetingId, String step, String status,
      {double percent = 0, String? detail, int etaMinutes = 0}) {
    _events.add(
      ImportProgressEvent(
        meetingId: meetingId,
        step: step,
        status: status,
        percent: percent,
        detail: detail,
        etaMinutes: etaMinutes,
      ),
    );
  }

  // ETA 公式（§7）：上传 = 剩余MB / 5MB/s × 1.5 弱网系数；分离 = 0.3×时长；
  // 转写 = 0.25×时长 + 轮询冗余 1；纪要 = 1。

  int _etaUploadMinutes(int remainingBytes) {
    if (remainingBytes <= 0) return 0;
    final double mb = remainingBytes / (1024 * 1024);
    return (mb / 5 / 60 * 1.5).ceil();
  }

  int _etaExtractMinutes(int durationMs) {
    if (durationMs <= 0) return 0;
    return (durationMs / 60000 * 0.3).ceil();
  }

  int _etaTranscribeMinutes(int durationMs) {
    if (durationMs <= 0) return 1;
    return (durationMs / 60000 * 0.25).ceil() + 1;
  }

  int _etaMinutesStep() => 1;
}
