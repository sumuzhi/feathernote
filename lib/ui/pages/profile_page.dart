/// 我的（屏 05）：用户卡 + 统计卡 + 两组设置 + 版本行。
///
/// 设置项展示**真实运行参数**（引擎、模型、采样率、降级原因），
/// 不是写死的演示值；开关为本地偏好（暂未落库）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart';
import '../../core/log/log.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/profile_screen.dart';
import '../theme/app_theme.dart';
import '../utils/exporter.dart';
import '../utils/placeholders.dart';
import '../widgets/app_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/surface_card.dart';

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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 自检面板需要「活读数」：录音中每秒刷新一次，便于用户/我们对照
    // 「帧数 / 会话是否就绪 / 已产句子数」实时定位链路断点。
    _tick = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> asyncMeetings = ref.watch(meetingsProvider);
    final List<MeetingSummary> meetings =
        asyncMeetings.value ?? const <MeetingSummary>[];
    final AsyncValue<HealthStatus> asyncHealth = ref.watch(healthProvider);
    final HealthStatus? health = asyncHealth.value;
    final RealtimeDiagnostics diagnostics =
        ref.watch(backendProvider).value?.diagnostics ??
            const RealtimeDiagnostics.empty();
    final String? degradedReason =
        ref.watch(backendBundleProvider).value?.degradedReason;
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
              subtitle: '纪要导出为文件',
              value: 'Markdown',
              onTap: () => _toast('导出格式：Markdown'),
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
        ProfileSectionView(
          title: '实时链路自检',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.cable_rounded,
              title: '引擎 / 降级',
              subtitle: degradedReason == null ? '实时链路 · 端化运行' : '已降级：$degradedReason',
              value: diagnostics.engineName,
              onTap: () => _toast('引擎：${diagnostics.engineName}'),
            ),
            ProfileSettingView(
              icon: Icons.bolt_rounded,
              title: '实时会话',
              subtitle: diagnostics.active
                  ? '会话 ${_short(diagnostics.sessionId)} · 会议 ${_short(diagnostics.meetingId)}'
                  : '当前无活动录音',
              value: diagnostics.realtimeRunning ? '已就绪' : '未连接',
              onTap: () => _toast(
                diagnostics.realtimeRunning ? '实时会话已就绪（收到 task-started）' : '实时会话未连接',
              ),
            ),
            ProfileSettingView(
              icon: Icons.graphic_eq_rounded,
              title: '已收帧 / 落盘',
              subtitle: '后端实际收到的音频证据',
              value: '${diagnostics.framesReceived} 帧 · ${diagnostics.pcmBytes ~/ 1024}KB',
              onTap: () => _toast('帧=${diagnostics.framesReceived} · PCM=${diagnostics.pcmBytes}B'),
            ),
            ProfileSettingView(
              icon: Icons.subtitles_rounded,
              title: '已产句子',
              subtitle: diagnostics.lastError == null
                  ? '实时转写产出'
                  : '最近错误：${_short(diagnostics.lastError)}',
              value: '${diagnostics.sentenceCount} 句',
              onTap: () => _toast('已产 ${diagnostics.sentenceCount} 句'),
            ),
          ],
        ),
        ProfileSectionView(
          title: '诊断',
          rows: <ProfileSettingView>[
            ProfileSettingView(
              icon: Icons.ios_share_rounded,
              title: '导出诊断日志',
              subtitle: '写入 exports/ 并显示绝对路径（缓冲最近 $logHistoryLength 条日志）',
              value: '导出',
              onTap: () => unawaited(_exportDiagnostics()),
            ),
          ],
        ),
      ],
      versionText: '版本 ${config.version} · 端化运行',
      diagnosticsPanel: _DiagnosticsPanel(
        lines: recentLogs(limit: 20),
        onExport: () => unawaited(_exportDiagnostics()),
      ),
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
      debugEntry: kDebugMode
          ? AppTextPillButton(
              label: '屏幕目录（debug）',
              soft: true,
              onTap: () => context.go('/gallery'),
            )
          : null,
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
      summaryStrategy: config.summaryStrategy,
      languageLabel: language,
      version: config.version,
    );
  }

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);

  /// 导出诊断日志（自检读数 + 最近日志）到 `exports/diagnostic-<时间戳>.log`。
  Future<void> _exportDiagnostics() async {
    try {
      final String path = await exportTextFile(
        fileName: 'diagnostic-${_stamp()}',
        content: _diagnosticReport(),
        extension: '.log',
      );
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
        '诊断日志已导出：$path',
        tone: ToastTone.success,
        duration: const Duration(seconds: 6),
      );
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
        '导出诊断日志失败：$error',
        tone: ToastTone.warning,
      );
    }
  }

  /// 诊断报告正文（自检读数 + 全量日志缓冲）。
  String _diagnosticReport() {
    final RealtimeDiagnostics diag =
        ref.read(backendProvider).value?.diagnostics ??
            const RealtimeDiagnostics.empty();
    final List<String> header = <String>[
      '==== 智能会议纪要 · 诊断日志 ====',
      '导出时间: ${DateTime.now().toIso8601String()}',
      '引擎: ${diag.engineName}',
      '实时会话: ${diag.active ? (diag.realtimeRunning ? '已连接' : '未连接') : '无活动录音'}',
      'session: ${diag.sessionId ?? '—'}',
      'meeting: ${diag.meetingId ?? '—'}',
      '后端收帧: ${diag.framesReceived}  落盘PCM: ${diag.pcmBytes}B  实时句子: ${diag.sentenceCount}',
      '最近错误: ${diag.lastError ?? '—'}',
      '---- 日志缓冲 ${recentLogs().length} 条 ----',
    ];
    return '${header.join('\n')}\n${dumpLogs()}\n';
  }

  /// 文件名时间戳（`yyyyMMdd-HHmmss`）。
  static String _stamp() {
    final DateTime now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// 把过长的 ID / 错误文案压缩到一行可读（自检面板用）。
  static String _short(String? value, {int max = 28}) {
    if (value == null || value.isEmpty) return '—';
    return value.length <= max ? value : '${value.substring(0, max)}…';
  }
}

/// 「我的」页展示用的配置投影（避免直接依赖 `AppConfig` 的 40 个字段）。
class AppConfigView {
  /// 构造投影。
  const AppConfigView({
    required this.llmModel,
    required this.realtimeModel,
    required this.summaryStrategy,
    required this.languageLabel,
    required this.version,
  });

  /// 纪要模型。
  final String llmModel;

  /// 实时转写模型。
  final String realtimeModel;

  /// 摘要策略。
  final String summaryStrategy;

  /// 语种文案。
  final String languageLabel;

  /// 版本号。
  final String version;
}

/// 诊断面板：导出按钮 + 最近日志预览（用户跑一次后可直接截图/导出）。
class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.lines, required this.onExport});

  final List<String> lines;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('最近日志（${lines.length} 条）', style: AppTextStyles.meta),
              AppTextPillButton(
                label: '导出诊断日志',
                soft: true,
                onTap: onExport,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            Text('暂无日志', style: AppTextStyles.metaSmall)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final String line in lines.reversed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(
                          line,
                          style: AppTextStyles.metaSmall.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
