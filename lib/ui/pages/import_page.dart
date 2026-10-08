/// 导入页：屏 14（选择文件）与屏 15（处理中）同页文件切换。
///
/// 页面只做「状态 → 视图数据」翻译 + 交互编排（选文件 → 预检 → startImport →
/// 跳屏 15；取消 / 后台处理 / 查看纪要），视觉交给 `lib/ui/screens/`。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../backend/backend_api.dart';
import '../../backend/services/import_service.dart';
import '../../core/config/app_config.dart';
import '../../core/error/app_error.dart';
import '../../core/log/log.dart';
import '../../domain/enums.dart';
import '../../domain/meeting.dart';
import '../../domain/segment.dart';
import '../../domain/speaker.dart';
import '../providers/app_providers.dart';
import '../providers/import_controller.dart';
import '../screens/import_idle_screen.dart';
import '../screens/import_processing_screen.dart';
import '../utils/formatters.dart';
import '../widgets/app_toast.dart';
import '../widgets/history_card.dart';

/// 音频扩展名白名单（设计 §7）。
const Set<String> kImportAudioExt = <String>{
  'm4a', 'aac', 'mp3', 'wav', 'flac', 'ogg', 'opus', 'amr',
};

/// 视频扩展名白名单（设计 §7；mkv/avi/webm 等一律在此拦截）。
const Set<String> kImportVideoExt = <String>{'mp4', 'mov', 'm4v'};

/// 已知视频封装（白名单外，用「请转成 mp4」文案）。
const Set<String> kVideoLikeExt = <String>{'mkv', 'avi', 'webm', 'wmv', 'flv', 'ts', '3gp'};

/// 导入页（屏 14）。
class ImportPage extends ConsumerStatefulWidget {
  /// 构造导入页。
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  bool _picking = false;
  bool _starting = false;

  /// 选文件 → 客户端预检 → startImport → 跳屏 15。
  Future<void> _pickAndStart() async {
    if (_picking || _starting) return;
    setState(() => _picking = true);
    String? srcPath;
    String? srcName;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        // 拿原始路径走流式上传；不整份读进内存。
        withData: false,
      );
      final PlatformFile? file = result?.files.single;
      srcPath = file?.path;
      srcName = file?.name;
    } catch (error) {
      logWarn('import', '文件选择器失败：$error');
      if (mounted) {
        ref.read(toastProvider.notifier).show('无法打开文件选择器，请重试', tone: ToastTone.warning);
      }
      if (mounted) setState(() => _picking = false);
      return;
    }
    if (mounted) setState(() => _picking = false);
    if (srcPath == null || srcName == null || srcPath.isEmpty) return; // 用户取消

    // ── 客户端预检（第一道门，设计 §7）──
    final AppConfig cfg = ref.read(appConfigProvider);
    final String ext = p.extension(srcName).replaceAll('.', '').toLowerCase();
    if (ext.isEmpty) {
      ref.read(toastProvider.notifier).show('无法识别的文件类型', tone: ToastTone.warning);
      return;
    }
    final bool isAudio = kImportAudioExt.contains(ext);
    final bool isVideo = kImportVideoExt.contains(ext);
    if (!isAudio && !isVideo) {
      ref.read(toastProvider.notifier).show(
            kVideoLikeExt.contains(ext) ? '暂不支持，请转成 mp4 后重试' : '暂不支持该音频格式',
            tone: ToastTone.warning,
          );
      return;
    }
    final int sizeBytes = File(srcPath).lengthSync();
    final int maxBytes = cfg.importMaxMb * 1024 * 1024;
    if (sizeBytes > maxBytes) {
      ref.read(toastProvider.notifier).show(
            '单个文件需小于 ${cfg.importMaxMb ~/ 1024}GB，当前文件 ${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)}GB',
            tone: ToastTone.warning,
          );
      return;
    }

    // ── startImport（第二道预检 probeMedia 在服务内）──
    setState(() => _starting = true);
    try {
      final BackendApi api = await ref.read(backendProvider.future);
      final Meeting meeting = await api.startImport(
        ImportRequest(
          srcPath: srcPath,
          srcName: srcName,
          isVideo: isVideo,
          sizeBytes: sizeBytes,
        ),
      );
      if (!mounted) return;
      unawaited(context.push('/import/${meeting.id}', extra: meeting));
    } on AppError catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(error.message, tone: ToastTone.warning);
    } catch (error) {
      logWarn('import', 'startImport 失败：$error');
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('导入启动失败，请重试', tone: ToastTone.warning);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> meetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> list = meetings.value ?? const <MeetingSummary>[];
    final DateTime now = DateTime.now();
    // 「最近导入」：source=imported 最近 5 条（设计 §9 Q1；筛选器为 P2 不做）。
    final List<MeetingSummary> imported = list
        .where((MeetingSummary item) => item.source == MeetingSource.imported)
        .toList(growable: false);
    final List<HistoryItemView> recent = <HistoryItemView>[
      for (int i = 0; i < imported.length && i < 5; i++)
        _importItemView(
          imported[i],
          now,
          onTap: () => context.push('/meeting/${imported[i].id}'),
        ),
    ];

    return ImportIdleScreen(
      onPickFile: _pickAndStart,
      picking: _picking || _starting,
      recentItems: recent,
      onTabTap: _onTabTap,
    );
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 2:
        context.go('/profile');
      default:
        break;
    }
  }
}

/// 屏 15（处理中）。
class ImportProcessingPage extends ConsumerStatefulWidget {
  /// 构造屏 15；[initialMeeting] 由屏 14 push 的 `extra` 带入（首帧免等待）。
  const ImportProcessingPage({super.key, required this.meetingId, this.initialMeeting});

  /// 会议 ID。
  final String meetingId;

  /// 首帧会议（可空：从历史页深链进入时为 null，稍后由库回填）。
  final Meeting? initialMeeting;

  @override
  ConsumerState<ImportProcessingPage> createState() => _ImportProcessingPageState();
}

class _ImportProcessingPageState extends ConsumerState<ImportProcessingPage> {
  bool _cancelling = false;

  /// 一次性拉取的全量 Meeting（拿 importMetaJson 判断音视频；summary 流没有 meta）。
  Meeting? _loaded;
  bool _loadRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(importProcessingProvider.notifier).resetFor(widget.meetingId);
    });
  }

  /// 组装当前会议视图：优先一次性全量 Meeting，否则由 summary 流兜底投影。
  Meeting? _resolveMeeting(List<MeetingSummary> summaries) {
    if (_loaded != null && _loaded!.id == widget.meetingId) return _loaded;
    for (final MeetingSummary item in summaries) {
      if (item.id != widget.meetingId) continue;
      return Meeting(
        id: item.id,
        title: item.title,
        createdAt: item.createdAt,
        durationMs: item.durationMs,
        sampleRate: 16000,
        speakerCount: item.speakerCount,
        status: MeetingStatus.stopped,
        source: item.source,
        finalizeStatus: item.finalizeStatus,
        transcriptSource: TranscriptSource.realtime,
        audioStatus: AudioStatus.none,
        audioBytes: 0,
        minutesPartial: false,
        segments: const <TranscriptSegment>[],
        speakers: const <Speaker>[],
        importStatus: item.importStatus,
      );
    }
    return widget.initialMeeting;
  }

  @override
  Widget build(BuildContext context) {
    // 全量 Meeting 一次性拉取（拿 importMetaJson 的 kind 判断音视频）。
    if (!_loadRequested) {
      _loadRequested = true;
      _loadOnce();
    }
    final AsyncValue<List<MeetingSummary>> meetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> summaries = meetings.value ?? const <MeetingSummary>[];
    final ImportProcessingState? snapshot = ref.watch(importProcessingProvider);
    final Meeting? meeting = _resolveMeeting(summaries);
    if (meeting == null) {
      // 会议不存在（已删除 / 深链错误）：直接回上一页。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      });
      return const SizedBox.shrink();
    }

    final String metaKind = _kindOf(meeting);
    final bool isVideo = metaKind == 'video';

    // 事件快照（屏 15 增量驱动源）。
    final ImportProcessingState state = (snapshot?.meetingId == widget.meetingId)
        ? snapshot!
        : ImportProcessingState.initial(widget.meetingId);

    // 库兜底（事件丢失时以库为准，设计 §8.1 双保险）。
    final ImportStatus dbStatus = meeting.importStatus;
    final Map<String, String> stepStatus = Map<String, String>.of(state.stepStatus);
    if (dbStatus == ImportStatus.done) {
      stepStatus[ImportService.stepUpload] = 'done';
      stepStatus[ImportService.stepExtract] ??= 'skip';
      stepStatus[ImportService.stepTranscribe] = 'done';
      stepStatus[ImportService.stepMinutes] = 'done';
    } else if (dbStatus == ImportStatus.extracting) {
      stepStatus[ImportService.stepUpload] = 'done';
      stepStatus[ImportService.stepExtract] = 'running';
    } else if (dbStatus == ImportStatus.transcribing) {
      stepStatus[ImportService.stepUpload] = 'done';
      stepStatus[ImportService.stepExtract] ??= 'skip';
      stepStatus[ImportService.stepTranscribe] = 'running';
    } else if (dbStatus == ImportStatus.minutes) {
      stepStatus[ImportService.stepUpload] = 'done';
      stepStatus[ImportService.stepExtract] ??= 'skip';
      stepStatus[ImportService.stepTranscribe] = 'done';
      stepStatus[ImportService.stepMinutes] = 'running';
    } else if (dbStatus == ImportStatus.failed) {
      // 失败步定位：把正在 running 的步标失败；都没 running 则按 kind 兜底。
      if (stepStatus[ImportService.stepTranscribe] == 'running') {
        stepStatus[ImportService.stepTranscribe] = 'failed';
      } else if (stepStatus[ImportService.stepMinutes] == 'running') {
        stepStatus[ImportService.stepMinutes] = 'failed';
      } else if (stepStatus[ImportService.stepUpload] == 'running') {
        stepStatus[ImportService.stepUpload] = 'failed';
      } else if (isVideo) {
        stepStatus[ImportService.stepExtract] = 'failed';
      } else {
        stepStatus[ImportService.stepUpload] = 'failed';
      }
    }

    final List<ImportStepView> steps = <ImportStepView>[
      ImportStepView(
        index: 1,
        title: '上传文件',
        subtitle: '上传到临时存储，24 小时后自动清除',
        status: stepStatus[ImportService.stepUpload] ?? 'idle',
        percent: state.uploadPercent > 0 ? state.uploadPercent : null,
      ),
      ImportStepView(
        index: 2,
        title: isVideo ? '分离音轨' : '解析音频',
        subtitle: isVideo ? '提取音频轨为 m4a，不解码零转码' : '读取音频元信息',
        status: isVideo
            ? (stepStatus[ImportService.stepExtract] ?? 'idle')
            : (stepStatus[ImportService.stepExtract] == 'failed' ? 'failed' : 'skip'),
        skip: !isVideo && stepStatus[ImportService.stepExtract] != 'failed',
      ),
      ImportStepView(
        index: 3,
        title: '语音转写',
        subtitle: '区分说话人 · 生成逐字稿',
        status: stepStatus[ImportService.stepTranscribe] ?? 'idle',
      ),
      ImportStepView(
        index: 4,
        title: '纪要生成',
        subtitle: '基于逐字稿生成结构化纪要',
        status: stepStatus[ImportService.stepMinutes] ?? 'idle',
      ),
    ];

    final bool allDone = dbStatus == ImportStatus.done ||
        (stepStatus[ImportService.stepUpload] == 'done' &&
            stepStatus[ImportService.stepMinutes] == 'done');
    final bool failed = dbStatus == ImportStatus.failed ||
        steps.any((ImportStepView s) => s.status == 'failed' || s.status == 'cancelled');

    return ImportProcessingScreen(
      title: meeting.title,
      subtitle: isVideo ? '视频导入 · 仅解析音轨' : '音频导入',
      isVideo: isVideo,
      steps: steps,
      detail: failed ? (meeting.importError ?? state.detail) : state.detail,
      etaMinutes: allDone || failed ? 0 : state.etaMinutes,
      allDone: allDone,
      onBack: () => context.canPop() ? context.pop() : context.go('/'),
      onCancel: failed || allDone
          ? () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            }
          : _confirmCancel,
      onViewMinutes: () => context.pushReplacement('/meeting/${widget.meetingId}'),
      onTabTap: _onTabTap,
    );
  }

  Future<void> _loadOnce() async {
    try {
      final BackendApi api = await ref.read(backendProvider.future);
      final Meeting? meeting = await api.getMeeting(widget.meetingId);
      if (mounted && meeting != null) {
        setState(() => _loaded = meeting);
      }
    } catch (_) {
      // 深链且会议不存在：保持 summary 兜底渲染。
    }
  }

  String _kindOf(Meeting meeting) {
    final String? meta = meeting.importMetaJson;
    if (meta != null && meta.contains('"video"')) return 'video';
    return 'audio';
  }

  /// 「取消处理」确认 → cancelImport → failed('用户取消')（设计 §4.3）。
  Future<void> _confirmCancel() async {
    if (_cancelling) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('取消本次导入？'),
        content: const Text('已上传的部分会被丢弃，可在历史页对该会议重试。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续处理'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消导入'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final BackendApi api = await ref.read(backendProvider.future);
      await api.cancelImport(widget.meetingId);
    } catch (error) {
      logWarn('import', '取消导入失败：$error');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/history');
      case 2:
        context.go('/profile');
      default:
        break;
    }
  }
}

/// 导入会议 → 历史卡片视图（「导入」badge + 处理中角标，设计 §8.1）。
HistoryItemView _importItemView(MeetingSummary item, DateTime now, {VoidCallback? onTap}) {
  final bool processing = item.importStatus == ImportStatus.importPending ||
      item.importStatus == ImportStatus.extracting ||
      item.importStatus == ImportStatus.transcribing ||
      item.importStatus == ImportStatus.minutes;
  final bool failed = item.importStatus == ImportStatus.failed;
  return HistoryItemView(
    title: item.title,
    description: failed
        ? (item.minutesExcerpt.isEmpty ? '导入失败，可进入详情页重试' : item.minutesExcerpt)
        : (processing ? '导入处理中，完成后自动生成纪要' : '来自视频 / 音频导入'),
    meta: '${formatDurationCn(item.durationMs)} · ${formatDayTime(item.createdAt, now: now)}',
    badge: failed ? HistoryBadge.importFailed : HistoryBadge.imported,
    processing: processing,
    onTap: onTap,
  );
}
