/// 「我的」页（设计稿 05 号屏）：设置与运行信息。
///
/// 本版本**无账号体系**，因此这里不做假登录，只展示真实运行参数
/// （引擎 / 模型 / 存储 / schema 版本 / 会议数量），便于现场排查。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart';
import '../../backend/di.dart';
import '../../core/config/app_config.dart';
import '../../core/log/log.dart' show logLevel;
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/placeholders.dart';
import '../widgets/surface_card.dart';

/// 「我的」页。
class ProfilePage extends ConsumerWidget {
  /// 构造我的页。
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    final BackendBundle? bundle = ref.watch(backendBundleProvider).value;
    final AsyncValue<HealthStatus> health = ref.watch(healthProvider);
    final String engineName = bundle?.engineName ?? config.engineProvider;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, AppSpacing.gapLg),
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: AppSpacing.minTap,
                height: AppSpacing.minTap,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  kUserDisplayName.characters.first,
                  style: AppTextStyles.label.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: AppSpacing.gapSm),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(kUserDisplayName, style: AppTextStyles.heroTitle),
                  Text('本地优先 · 数据不出设备', style: AppTextStyles.metaSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gapLg),
          if (bundle?.degradedReason != null) ...<Widget>[
            _Notice(text: '当前为离线示例引擎（Mock）：${bundle!.degradedReason}'),
            const SizedBox(height: AppSpacing.gapSm),
          ],
          const _SectionTitle('引擎与模型'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                _SettingRow(label: '运行时引擎', value: engineName),
                _SettingRow(label: '实时识别模型', value: config.realtimeModel),
                _SettingRow(label: '终稿转写模型', value: config.filetransModel),
                _SettingRow(
                  label: '说话人分离',
                  value: config.filetransDiarization ? '已开启' : '已关闭',
                ),
                _SettingRow(label: '纪要模型', value: config.llmModel),
                _SettingRow(label: '纪要策略', value: config.summaryStrategy),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          const _SectionTitle('录音与存储'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                _SettingRow(label: '采样率', value: '${config.sampleRate} Hz · 单声道'),
                _SettingRow(label: '音频归档', value: config.audioStorage == 'local' ? '本地文件' : 'COS'),
                _SettingRow(label: '单文件上限', value: '${config.uploadMaxMb} MB'),
                _SettingRow(
                  label: '本地调试服务',
                  value: config.enableLocalHttp ? '已挂载 :${config.localHttpPort}' : '未挂载',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          const _SectionTitle('诊断'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                _SettingRow(label: '日志级别', value: logLevel),
                _SettingRow(
                  label: '数据库 schema',
                  value: health.when(
                    data: (HealthStatus status) => 'v${status.schemaVersion ?? '?'}',
                    loading: () => '检测中…',
                    error: (Object error, StackTrace stack) => '读取失败',
                  ),
                ),
                _SettingRow(
                  label: '会议数量',
                  value: health.when(
                    data: (HealthStatus status) => '${status.meetingCount}',
                    loading: () => '检测中…',
                    error: (Object error, StackTrace stack) => '—',
                  ),
                ),
                _SettingRow(label: '应用版本', value: config.version),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          const _SectionTitle('关于'),
          const SurfaceCard(
            padding: EdgeInsets.all(AppSpacing.card),
            child: Text(
              '智能会议纪要 · 移动端\n'
              '录音 → 实时转写 → 终稿转写（说话人分离）→ AI 结构化纪要，全流程在本机完成。\n'
              '如需 COS 归档 / 知识库，本版本暂不提供。',
              style: AppTextStyles.meta,
            ),
          ),
          const SizedBox(height: AppSpacing.gapLg),
          Center(
            child: TextButton(
              onPressed: () => context.go('/'),
              child: const Text('返回录音页', style: AppTextStyles.link),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.gapSm, left: 2),
      child: Text(text, style: AppTextStyles.itemTitle.copyWith(fontSize: 15)),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.card, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label, style: AppTextStyles.meta),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.badgeOrangeBg,
        borderRadius: BorderRadius.circular(AppRadius.infoBar),
      ),
      child: Text(
        text,
        style: AppTextStyles.metaSmall.copyWith(color: AppColors.badgeOrangeFg),
      ),
    );
  }
}
