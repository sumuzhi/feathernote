/// 设置页（原「我的」屏 05：App 无登录，用户卡与统计卡已移除）。
///
/// 设置项展示**真实运行参数**（引擎、模型、采样率），不是写死的演示值；
/// 开关为本地偏好（暂未落库）。导出位置持久化在应用文档目录（见
/// `export_destination.dart`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../backend/backend_api.dart' show HealthStatus;
import '../../core/platform/recording_foreground_service.dart';
import '../../core/update/app_update.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/profile_screen.dart';
import '../theme/app_theme.dart';
import '../utils/backup_exporter.dart';
import '../utils/export_destination.dart';
import '../utils/exporter.dart' show ExportCancelledException;
import '../widgets/app_toast.dart';
import '../widgets/export_destination_sheet.dart';
import '../widgets/update_dialog.dart';

/// 设置页。
class ProfilePage extends ConsumerStatefulWidget {
  /// 构造设置页。
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _diarization = true;
  ExportDestination _destination = ExportDestination.appDownload;
  bool _checkingUpdate = false;
  bool _exportingBackup = false;
  double _exportProgress = 0;
  BackupCancelToken? _exportCancel;

  /// 真实版本号（来自 `package_info_plus`，随 pubspec bump 自动更新）。
  ///
  /// 历史缺陷：此前展示走 `AppConfig.version`（`--dart-define` 非 const 读法
  /// 在 AOT 下不折叠）→ 永远显示写死的「1.0.0」，不随发布变化。
  /// null = 平台通道不可用（测试环境），回落到配置值。
  String? _pkgVersion;

  @override
  void initState() {
    super.initState();
    _loadDestination();
    _loadPackageVersion();
  }

  Future<void> _loadPackageVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _pkgVersion = info.version);
    } catch (_) {
      // 测试环境 / 平台通道不可用：保持 null，展示回落到配置值。
    }
  }

  Future<void> _loadDestination() async {
    final ExportDestination saved = await loadExportDestination();
    if (!mounted) return;
    setState(() => _destination = saved);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> asyncMeetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> meetings =
        asyncMeetings.value ?? const <MeetingSummary>[];
    final AsyncValue<HealthStatus> asyncHealth = ref.watch(healthProvider);
    final HealthStatus? health = asyncHealth.value;
    final AppConfigView config = _configView();
    int totalMs = 0;
    int summarized = 0;
    for (final MeetingSummary item in meetings) {
      totalMs += item.durationMs;
      if (item.hasMinutes) summarized++;
    }

    return ProfileScreen(
      stats: <ProfileStatView>[
        ProfileStatView(value: '${meetings.length}', label: '场会议'),
        ProfileStatView(value: _formatHours(totalMs), label: '累计时长'),
        ProfileStatView(value: '$summarized', label: '场已总结'),
      ],
      sections: <ProfileSectionView>[
        ProfileSectionView(
          title: '导出',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.folder_open_rounded,
              title: '导出位置',
              subtitle: '纪要 / 转写导出文件的保存位置',
              value: exportDestinationLabel(_destination),
              onTap: _pickDestination,
            ),
          ],
        ),
        ProfileSectionView(
          title: '模型与转写',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.auto_awesome_rounded,
              title: '纪要模型',
              subtitle: '摘要策略 · ${config.summaryStrategy}',
              value: config.llmModel,
              onTap: () => _toast('纪要模型：${config.llmModel}'),
            ),
            ProfileSettingView(
              icon: Icons.translate_rounded,
              title: '转写语言',
              subtitle: '云端 ASR · ${config.realtimeModel}',
              value: config.languageLabel,
              onTap: () => _toast('转写语言：${config.languageLabel}'),
            ),
            ProfileSettingView(
              icon: Icons.groups_rounded,
              title: '说话人分离',
              subtitle: '声纹聚类 · 自动标注',
              toggle: true,
              toggleValue: _diarization,
              switchLabel: '说话人分离',
              onToggle: (bool value) => setState(() => _diarization = value),
            ),
          ],
        ),
        ProfileSectionView(
          title: '数据与存储',
          rows: <ProfileSettingView>[
            // 用户要求：移除「音频留存」开关——音频一律留存于本地归档。
            ProfileSettingView(
              icon: Icons.storage_rounded,
              title: '数据库',
              subtitle:
                  'SQLite · schema ${health?.schemaVersion ?? '—'} · $summarized 场已总结 · 点击导出备份',
              value: _exportingBackup ? null : '${meetings.length} 条',
              trailingOverride:
                  _exportingBackup ? _buildExportTrailing() : null,
              onTap: _exportBackup,
            ),
          ],
        ),
        ProfileSectionView(
          title: '运行参数',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.memory_rounded,
              title: '转写引擎',
              subtitle: health?.message ?? '本地进程内后端',
              value: health?.engineName ?? '装配中…',
              onTap: () => _toast('引擎：${health?.engineName ?? '—'}'),
            ),
            ProfileSettingView(
              icon: Icons.layers_rounded,
              title: '版本',
              subtitle: config.buildStamp.isEmpty
                  ? '端化运行 · 本地进程内后端 · 点击检查更新'
                  : '端化运行 · ${config.buildStamp} · 点击检查更新',
              value: _checkingUpdate ? '检查中…' : config.version,
              onTap: _checkUpdateManually,
            ),
          ],
        ),
      ],
      onSettings: () => _toast('智能会议纪要 · 端化运行'),
      onTabTap: (int index) {
        switch (index) {
          case 0:
            context.go('/');
          case 1:
            context.go('/history');
          default:
            break;
        }
      },
      selectedTab: 2,
    );
  }

  /// 弹出导出位置选择并持久化。
  Future<void> _pickDestination() async {
    final ExportDestination? picked = await showExportDestinationSheet(context);
    if (picked == null || !mounted) return;
    await saveExportDestination(picked);
    if (!mounted) return;
    setState(() => _destination = picked);
  }

  /// 手动检查更新（点击「版本」行）。
  ///
  /// 走 [AppUpdateChecker.checkStrict]（失败抛出），与启动期静默检查区分：
  /// 有更新 → 复用启动期同一个更新弹窗；无更新 → toast「已是最新」；
  /// 网络失败 → toast 可读错误（绝不把故障伪装成「已是最新」）。
  Future<void> _checkUpdateManually() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final UpdateDecision decision = await AppUpdateChecker(
        manifestUrl: ref.read(appConfigProvider).updateManifestUrl,
      ).checkStrict();
      if (!mounted) return;
      if (decision.available && decision.remote != null) {
        await showAppUpdateDialog(context, decision.remote!);
      } else {
        // 用户要求：仅提示「已是最新」，不展示过多信息。
        _toast('当前已是最新版本');
      }
    } catch (error) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('检查更新失败：请检查网络后重试', tone: ToastTone.warning);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// 导出进度 / 取消的自定义右侧组件（导出中显示）。
  Widget _buildExportTrailing() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 84,
          height: 6,
          child: LinearProgressIndicator(
            value: _exportProgress,
            backgroundColor: AppColors.line,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.orange),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(_exportProgress * 100).round()}%',
          style: AppTextStyles.metaSmall,
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => _exportCancel?.cancel(),
          behavior: HitTestBehavior.opaque,
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  /// 数据备份（用户确认的内容：含音频全量 ZIP = backup.json + 各会议 md + 音频）。
  ///
  /// 点击「数据库」行触发；重活在**后台 isolate** 执行，UI 不阻塞；导出中显示
  /// 进度条 + 取消；并借前台服务保活，切后台 / 锁屏不被系统回收。
  Future<void> _exportBackup() async {
    if (_exportingBackup) return;
    setState(() {
      _exportingBackup = true;
      _exportProgress = 0;
    });
    final BackupCancelToken token = BackupCancelToken();
    _exportCancel = token;
    // 前台服务保活：导出（含可能的数分钟 ZIP 打包）期间进程不被系统回收。
    await RecordingForegroundService.instance.acquire(
      'export',
      notificationText: '正在导出数据备份，点击回到应用',
    );
    try {
      final api = await ref.read(backendProvider.future);
      final int? schemaVersion =
          (await ref.read(healthProvider.future)).schemaVersion;
      final List<MeetingSummary> summaries =
          ref.read(meetingsProvider).value ?? const <MeetingSummary>[];
      final List<Meeting> meetings = <Meeting>[];
      for (final MeetingSummary summary in summaries) {
        final Meeting? meeting = await api.getMeeting(summary.id);
        if (meeting != null) meetings.add(meeting);
      }
      final ({String location, BackupCancelToken handle}) result =
          await exportBackup(
        meetings: meetings,
        destination: _destination,
        schemaVersion: schemaVersion,
        audioPathResolver: (Meeting meeting) => api.getAudioPath(meeting.id),
        cancelToken: token,
        onProgress: (double fraction, String phase) {
          if (!mounted) return;
          setState(() {
            _exportProgress = fraction;
          });
        },
      );
      if (!mounted) return;
      // 位置标签是短文案（如 Download/SmartMinutes 或文件名），绝不含应用
      // 内部绝对路径——那既撑爆 toast 也对用户无意义（无法访问 /data）。
      ref
          .read(toastProvider.notifier)
          .show('备份已导出到 ${result.location}', tone: ToastTone.success);
    } on ExportCancelledException {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('已取消导出', tone: ToastTone.info);
      return;
    } catch (error) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('备份导出失败：$error', tone: ToastTone.warning);
    } finally {
      await RecordingForegroundService.instance.release('export');
      if (mounted) {
        setState(() {
          _exportingBackup = false;
          _exportCancel = null;
        });
      }
    }
  }

  /// 累计时长展示：不满 1 小时用 0.xh（保留 1 位小数，最小 0.1h）；
  /// 满 1 小时取整小时（如 64h）。
  String _formatHours(int totalMs) {
    if (totalMs <= 0) return '0h';
    final double hours = totalMs / 3600000;
    if (hours < 1) {
      final double value = (totalMs / 60000) / 60;
      final double rounded = double.parse(value.toStringAsFixed(1));
      return '${rounded < 0.1 ? 0.1 : rounded}h';
    }
    return '${hours.toStringAsFixed(0)}h';
  }

  AppConfigView _configView() {    final config = ref.watch(appConfigProvider);
    final bool zh = config.filetransLanguageHints.contains('zh');
    final bool en = config.filetransLanguageHints.contains('en');
    final String language = zh && en
        ? '中英文自动'
        : (zh ? '中文' : (en ? '英文' : '自动识别'));
    return AppConfigView(
      llmModel: config.llmModel,
      realtimeModel: config.realtimeModel,
      filetransModel: config.filetransModel,
      summaryStrategy: config.summaryStrategy,
      languageLabel: language,
      version: _pkgVersion ?? config.version,
      buildStamp: config.buildStamp,
    );
  }

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);
}

/// 「设置」页展示用的配置投影（避免直接依赖 `AppConfig` 的 40 个字段）。
class AppConfigView {
  /// 构造投影。
  const AppConfigView({
    required this.llmModel,
    required this.realtimeModel,
    required this.filetransModel,
    required this.summaryStrategy,
    required this.languageLabel,
    required this.version,
    this.buildStamp = '',
  });

  /// 纪要模型。
  final String llmModel;

  /// 实时转写模型。
  final String realtimeModel;

  /// 终稿（filetrans）模型。
  final String filetransModel;

  /// 摘要策略。
  final String summaryStrategy;

  /// 语种文案。
  final String languageLabel;

  /// 版本号。
  final String version;

  /// 构建戳（空串表示未注入）。
  final String buildStamp;
}
