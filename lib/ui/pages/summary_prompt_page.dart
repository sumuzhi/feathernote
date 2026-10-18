/// 总结 Prompt 管理页：3 个预置 + 用户自定义，**点卡片任意位置即切换**，
/// 切换后 Toast 提示「下次总结生效」（用户要求：不用底部 SnackBar）。
///
/// 新建/编辑走**路由页**（/summary-prompt/edit，用户要求：弹窗操作区域太小、
/// 键盘压缩内容导致溢出）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/prompts.dart' show kMinutesPromptAsset;
import '../../backend/services/summary_prompts.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// 总结 Prompt 管理页（压栈页，返回回设置页）。
class SummaryPromptPage extends ConsumerStatefulWidget {
  /// 构造。
  const SummaryPromptPage({super.key});

  @override
  ConsumerState<SummaryPromptPage> createState() => _SummaryPromptPageState();
}

class _SummaryPromptPageState extends ConsumerState<SummaryPromptPage> {
  SummaryPromptStore? _store;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final SummaryPromptStore store = await loadSummaryPromptStore();
    if (!mounted) return;
    setState(() => _store = store);
  }

  Future<void> _select(SummaryPrompt prompt) async {
    final SummaryPromptStore current = _store ?? const SummaryPromptStore();
    if (current.selectedId == prompt.id) return; // 已是当前选择：不重复提示
    final SummaryPromptStore next = current.copyWith(selectedId: prompt.id);
    await saveSummaryPromptStore(next);
    if (!mounted) return;
    setState(() => _store = next);
    ref.read(toastProvider.notifier).show(
          '「${prompt.name}」已选择，下次总结时生效',
          tone: ToastTone.success,
        );
  }

  Future<void> _openEditor({SummaryPrompt? existing}) async {
    // 压栈到全页编辑器；返回后刷新（新建/保存会改变列表与选中态）。
    await context.push('/summary-prompt/edit', extra: existing);
    await _reload();
  }

  Future<void> _deleteCustom(SummaryPrompt prompt) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除 Prompt'),
        content: Text('确定删除「${prompt.name}」？该操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final SummaryPromptStore current = _store ?? const SummaryPromptStore();
    final SummaryPromptStore next = current.copyWith(
      customs: current.customs
          .where((SummaryPrompt p) => p.id != prompt.id)
          .toList(growable: false),
      // 删除的正是选中项 → 回落到标准会议纪要。
      selectedId: current.selectedId == prompt.id
          ? SummaryPrompt.builtinCurrentId
          : null,
    );
    await saveSummaryPromptStore(next);
    if (!mounted) return;
    setState(() => _store = next);
    ref.read(toastProvider.notifier).show(
          '「${prompt.name}」已删除',
          tone: ToastTone.info,
        );
  }

  @override
  Widget build(BuildContext context) {
    final SummaryPromptStore? store = _store;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => context.pop(),
        ),
        title: Text('总结风格', style: AppTextStyles.subHead),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 26),
            tooltip: '新建自定义 Prompt',
            onPressed: () => _openEditor(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: store == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                Text(
                  '点击卡片即切换；下一次转写总结（含自动生成与手动重新生成）使用所选 Prompt，'
                  '生成进行中更换不影响当次。',
                  style: AppTextStyles.metaSmall,
                ),
                const SizedBox(height: 12),
                for (final SummaryPrompt prompt in store.allPrompts())
                  _PromptCard(
                    prompt: prompt,
                    selected: store.selectedId == prompt.id,
                    onSelect: () => _select(prompt),
                    onEdit:
                        prompt.builtin ? null : () => _openEditor(existing: prompt),
                    onDelete: prompt.builtin ? null : () => _deleteCustom(prompt),
                  ),
                const SizedBox(height: 16),
                Text(
                  '模板占位符：{{meeting_content}}（会议信息 + 逐字稿，必需）；'
                  '{{meeting_title}} / {{meeting_date}} / {{duration}} / '
                  '{{speaker_count}} / {{speaker_roster}} / {{transcript}}（可选）。',
                  style: AppTextStyles.metaSmall,
                ),
              ],
            ),
    );
  }
}

/// 单条 Prompt 卡片：**整卡点击即选择**（用户要求：不只点选择圆框）；
/// 选中态纯背景色（零位移）；预置不可编辑/删除。
class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.selected,
    required this.onSelect,
    this.onEdit,
    this.onDelete,
  });

  final SummaryPrompt prompt;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 整卡点击切换（含标题/描述区域）。
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeSoft : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card2),
          boxShadow: AppShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? AppColors.orange : AppColors.faint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prompt.name,
                    style: AppTextStyles.settingTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (prompt.builtin)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('预置', style: AppTextStyles.metaSmall),
                  ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: AppColors.muted,
                    onPressed: onEdit,
                    tooltip: '编辑',
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: AppColors.muted,
                    onPressed: onDelete,
                    tooltip: '删除',
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 2, 8, 0),
              child: Text(
                prompt.id == SummaryPrompt.builtinCurrentId
                    ? '既有知识萃取模板（$kMinutesPromptAsset）'
                    : _preview(prompt.content),
                style: AppTextStyles.metaSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _preview(String content) {
    final String flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.isEmpty ? '（空模板）' : flat;
  }
}
