/// 历史记录页（设计稿 04 / 08 / 09 / 10）。
///
/// 结构：标题 + 排序 ↔ → 搜索框 → 过滤 chips → 卡片列表（含空态 / 无结果态）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/backend_api.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_chips.dart';
import '../widgets/history_card.dart';
import '../widgets/search_field.dart';

/// 过滤项 id。
abstract final class HistoryFilter {
  /// 全部。
  static const String all = 'all';

  /// 今天。
  static const String today = 'today';

  /// 本周。
  static const String week = 'week';

  /// 已总结。
  static const String summarized = 'summarized';
}

/// 历史记录页。
class HistoryPage extends ConsumerStatefulWidget {
  /// 构造历史页。
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _filter = HistoryFilter.all;
  bool _newestFirst = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> async = ref.watch(meetingsProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 0),
            child: Row(
              children: <Widget>[
                const Expanded(child: Text('历史记录', style: AppTextStyles.pageTitle)),
                AppCircleButton(
                  icon: Icons.swap_vert_rounded,
                  tooltip: _newestFirst ? '当前：最新优先' : '当前：最旧优先',
                  onTap: () => setState(() => _newestFirst = !_newestFirst),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: AppSearchField(
              controller: _search,
              hintText: '搜索会议标题、纪要或待办…',
              onChanged: (String value) => setState(() => _query = value.trim()),
              onClear: () => setState(() => _query = ''),
            ),
          ),
          const SizedBox(height: AppSpacing.gapSm),
          FilterChips(
            options: const <FilterOption>[
              FilterOption(id: HistoryFilter.all, label: '全部'),
              FilterOption(id: HistoryFilter.today, label: '今天'),
              FilterOption(id: HistoryFilter.week, label: '本周'),
              FilterOption(id: HistoryFilter.summarized, label: '已总结'),
            ],
            selectedId: _filter,
            onSelected: (String id) => setState(() => _filter = id),
          ),
          const SizedBox(height: AppSpacing.gapSm),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (Object error, StackTrace stack) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: '读取历史失败',
                description: '$error',
                actionLabel: '重试',
                onAction: () => ref.invalidate(meetingsProvider),
              ),
              data: (List<MeetingSummary> meetings) => _buildList(meetings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<MeetingSummary> meetings) {
    if (meetings.isEmpty) {
      return ListView(
        children: const <Widget>[
          EmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: '还没有会议记录',
            description: '从「录音」页开始一次录音，结束后会自动生成纪要与完整转写',
          ),
        ],
      );
    }
    final List<MeetingSummary> filtered = _applyFilters(meetings);
    if (filtered.isEmpty) {
      return ListView(
        children: <Widget>[
          EmptyState(
            icon: Icons.search_off_rounded,
            title: _query.isEmpty ? '该筛选下暂无记录' : '没有找到「$_query」',
            description: _query.isEmpty ? '换个筛选条件试试' : '试试更短的关键词，或清除筛选条件',
            actionLabel: '清除筛选',
            onAction: () => setState(() {
              _search.clear();
              _query = '';
              _filter = HistoryFilter.all;
            }),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.gapLg,
      ),
      itemCount: filtered.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.gapSm),
      itemBuilder: (BuildContext context, int index) {
        final MeetingSummary meeting = filtered[index];
        return HistoryCard(
          summary: meeting,
          onTap: () => context.push('/meeting/${meeting.id}'),
          onRename: () => unawaited(_rename(meeting)),
          onDelete: () => unawaited(_delete(meeting)),
        );
      },
    );
  }

  List<MeetingSummary> _applyFilters(List<MeetingSummary> meetings) {
    final DateTime now = DateTime.now();
    final DateTime weekStart = now.subtract(const Duration(days: 7));
    final String query = _query.toLowerCase();
    final List<MeetingSummary> result = meetings.where((MeetingSummary meeting) {
      switch (_filter) {
        case HistoryFilter.today:
          final DateTime local = meeting.createdAt.toLocal();
          if (local.year != now.year || local.month != now.month || local.day != now.day) {
            return false;
          }
        case HistoryFilter.week:
          if (meeting.createdAt.toLocal().isBefore(weekStart)) return false;
        case HistoryFilter.summarized:
          if (!meeting.hasMinutes) return false;
        default:
          break;
      }
      if (query.isEmpty) return true;
      return meeting.title.toLowerCase().contains(query) ||
          meeting.minutesExcerpt.toLowerCase().contains(query);
    }).toList();
    result.sort(
      (MeetingSummary a, MeetingSummary b) => _newestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return result;
  }

  Future<BackendApi> _api() => ref.read(backendProvider.future);

  Future<void> _rename(MeetingSummary meeting) async {
    final TextEditingController controller = TextEditingController(text: meeting.title);
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('重命名', style: AppTextStyles.heroTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.body,
          decoration: const InputDecoration(hintText: '会议标题'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消', style: AppTextStyles.meta.copyWith(color: AppColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存', style: AppTextStyles.link),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || value == meeting.title) return;
    try {
      final BackendApi api = await _api();
      await api.updateMeeting(meeting.id, title: value);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('已重命名', tone: ToastTone.success);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('重命名失败：$error', tone: ToastTone.warning);
    }
  }

  Future<void> _delete(MeetingSummary meeting) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: const Text('删除这条记录？', style: AppTextStyles.heroTitle),
        content: Text(
          '「${meeting.title}」的纪要、转写与音频都会被删除，无法恢复。',
          style: AppTextStyles.body,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('取消', style: AppTextStyles.meta.copyWith(color: AppColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('删除', style: AppTextStyles.meta.copyWith(color: AppColors.recRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final BackendApi api = await _api();
      await api.deleteMeeting(meeting.id);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('已删除', tone: ToastTone.success);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('删除失败：$error', tone: ToastTone.warning);
    }
  }
}
