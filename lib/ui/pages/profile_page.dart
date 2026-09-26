/// 设置页（原「我的」屏 05：App 无登录，用户卡与统计卡已移除）。
///
/// 设置项展示**真实运行参数**（引擎、模型、采样率），不是写死的演示值；
/// 开关为本地偏好（暂未落库）。导出位置持久化在应用文档目录（见
/// `export_destination.dart`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart' show HealthStatus;
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/profile_screen.dart';
import '../utils/export_destination.dart';
import '../widgets/app_toast.dart';
import '../widgets/export_destination_sheet.dart';

/// 设置页。
class ProfilePage extends ConsumerStatefulWidget {
  /// 构造设置页。
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _diarization = true;
  bool _keepAudio = false;
  ExportDestination _destination = ExportDestination.appDownload;

  @override
  void initState() {
    super.initState();
    _loadDestination();
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
            ProfileSettingView(
              icon: Icons.wifi_off_rounded,
              title: '音频留存',
              subtitle: '转写后不保存原始音频',
              toggle: true,
              toggleValue: _keepAudio,
              switchLabel: '音频留存',
              onToggle: (bool value) => setState(() => _keepAudio = value),
            ),
            ProfileSettingView(
              icon: Icons.storage_rounded,
              title: '数据库',
              subtitle:
                  'SQLite · schema ${health?.schemaVersion ?? '—'} · $summarized 场已总结',
              value: '${meetings.length} 条',
              onTap: () => _toast('已存 ${meetings.length} 条会议'),
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
                  ? '端化运行 · 本地进程内后端'
                  : '端化运行 · ${config.buildStamp}',
              value: config.version,
              onTap: () => _toast('版本 ${config.version} · ${config.buildStamp}'),
            ),
          ],
        ),
      ],
      versionText: '版本 ${config.version} · 端化运行'
          '${config.buildStamp.isEmpty ? '' : ' · ${config.buildStamp}'}',
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
      version: config.version,
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
