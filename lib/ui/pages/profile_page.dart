/// 我的（屏 05）：用户卡 + 统计卡 + 设置组 + 版本行。
///
/// 设置项展示**真实运行参数**（引擎、模型、采样率），不是写死的演示值；
/// 开关为本地偏好（暂未落库）。
///
/// 注：「实时链路自检」「诊断」「屏幕目录」入口已按产品决定移除
/// （2026-09-25），诊断导出逻辑随之删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart' show HealthStatus;
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/profile_screen.dart';
import '../utils/placeholders.dart';
import '../widgets/app_toast.dart';

/// 我的页。
class ProfilePage extends ConsumerStatefulWidget {
  /// 构造我的页。
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _diarization = true;
  bool _keepAudio = false;

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
      userName: kUserDisplayName,
      userSubtitle: '专业版 · 云端转写',
      stats: <ProfileStatView>[
        ProfileStatView(value: '${meetings.length}', label: '场会议'),
        ProfileStatView(value: '${totalMs ~/ 3600000}h', label: '累计时长'),
        ProfileStatView(value: '$summarized', label: '场已总结'),
      ],
      sections: <ProfileSectionView>[
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
          title: '数据与导出',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.description_outlined,
              title: '导出格式',
              subtitle: '导出纪要时可选',
              value: 'MD / PDF / Word / TXT',
              onTap: () => _toast('在纪要页点「导出纪要」时选择格式'),
            ),
            ProfileSettingView(
              icon: Icons.wifi_off_rounded,
              title: '音频留存',
              subtitle: '转写后不保存原始音频',
              toggle: true,
              toggleValue: _keepAudio,
              switchLabel: '音频留存',
              onToggle: (bool value) => setState(() => _keepAudio = value),
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
              icon: Icons.storage_rounded,
              title: '数据库',
              subtitle: 'SQLite · schema ${health?.schemaVersion ?? '—'}',
              value: '${meetings.length} 条',
              onTap: () => _toast('已存 ${meetings.length} 条会议'),
            ),
          ],
        ),
      ],
      versionText: '版本 ${config.version} · 端化运行',
      onSettings: () => _toast('设置'),
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

  AppConfigView _configView() {
    final config = ref.watch(appConfigProvider);
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
    );
  }

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);
}

/// 「我的」页展示用的配置投影（避免直接依赖 `AppConfig` 的 40 个字段）。
class AppConfigView {
  /// 构造投影。
  const AppConfigView({
    required this.llmModel,
    required this.realtimeModel,
    required this.filetransModel,
    required this.summaryStrategy,
    required this.languageLabel,
    required this.version,
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
}
