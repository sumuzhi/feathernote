/// 总结风格页（ScreenFrame 设计语言，对齐「数据库」导出页）：
/// 预置 6 个 + 用户自定义，**点卡片任意位置即切换**，切换后 Toast 提示
/// 「下次总结生效」；新建/编辑走全页编辑器（/summary-prompt/edit）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/summary_prompts.dart';
import '../providers/app_providers.dart';
import '../screens/screen_frame.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';

/// 总结 Prompt 管理页（压栈页，返回回设置页）。
class SummaryPromptPage extends ConsumerStatefulWidget {
  /// 构造。
  const SummaryPromptPage({super.key});

  @override
  ConsumerState<SummaryPromptPage> createState() => _SummaryPromptPageState();
}

class _SummaryPromptPageState extends ConsumerState<SummaryPromptPage> {
  SummaryPromptStore? _store;

  /// 全量列表（预置 + 自定义）。
  ///
  /// 预置元信息来自 catalog.json（异步加载），所以不能在 build 里直接算，
  /// 必须在 [_reload] 里加载好缓存起来。
  List<SummaryPrompt> _prompts = const <SummaryPrompt>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final SummaryPromptStore store = await loadSummaryPromptStore();
    final List<SummaryPrompt> prompts = await store.allPrompts();
    if (!mounted) return;
    setState(() {
      _store = store;
      _prompts = prompts;
    });
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

  /// 基于预置项创建副本：读取其模板正文，作为内容填入编辑器。
  ///
  /// 预置本身保持只读（作为参考基准），但用户可以自由派生并修改副本，
  /// 这样既守住「标准答案」的意义，又不限制用户改造的自由。
  Future<void> _duplicate(SummaryPrompt prompt) async {
    final String content = await resolveTemplateOf(prompt);
    if (!mounted) return;
    // 传给编辑器的副本：id 留空（由编辑器生成 custom-<uuid>），名称加「副本」后缀。
    final SummaryPrompt seed = SummaryPrompt(
      id: '',
      name: '${prompt.name} 副本',
      content: content,
      builtin: false,
      description: '',
    );
    await context.push('/summary-prompt/edit', extra: seed);
    await _reload();
  }

  Future<void> _deleteCustom(SummaryPrompt prompt) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card2),
        ),
        title: Text('删除 Prompt', style: AppTextStyles.cardHead),
        content: Text(
          '确定删除「${prompt.name}」？该操作不可撤销。',
          style: AppTextStyles.body15,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: AppTextStyles.action),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除',
                style: AppTextStyles.action.copyWith(color: AppColors.red)),
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
      // 删除的正是选中项 → 回落到 catalog 第一项（标准会议纪要）。
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
    final int customCount = store?.customs.length ?? 0;

    return ScreenFrame(
      scrollable: true,
      bottomSpacer: 32 + MediaQuery.viewPaddingOf(context).bottom,
      header: AppTopBar(
        title: '总结风格',
        subtitle: '预置 ${_prompts.length - customCount} 个 · 自定义 $customCount 个'
            ' · 点卡片即切换',
        leadingIcon: Icons.chevron_left_rounded,
        onLeading: () => context.pop(),
        actionIcon: Icons.add_rounded,
        onAction: () => _openEditor(),
        actionTooltip: '新建 Prompt',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 顶部说明行（横向边距对齐导出页控制行）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Text(
              '下一次转写总结（含自动生成与手动重新生成）使用所选 Prompt；'
              '生成进行中更换不影响当次。',
              style: AppTextStyles.metaSmall,
            ),
          ),
          const SizedBox(height: 4),
          for (final SummaryPrompt prompt in _prompts)
            _PromptCard(
              prompt: prompt,
              selected: store?.selectedId == prompt.id,
              onSelect: () => _select(prompt),
              onEdit:
                  prompt.builtin ? null : () => _openEditor(existing: prompt),
              onDelete: prompt.builtin ? null : () => _deleteCustom(prompt),
              // 预置项提供「另存为副本」，让用户能在官方模板基础上改造。
              onDuplicate: prompt.builtin ? () => _duplicate(prompt) : null,
            ),
          const SizedBox(height: 16),
          // 占位符说明（横向边距对齐导出页 meta 信息行）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Text(
              '模板占位符：{{meeting_content}}（会议信息 + 逐字稿，必需）；'
              '{{meeting_title}} / {{meeting_date}} / {{duration}} / '
              '{{speaker_count}} / {{speaker_roster}} / {{transcript}}（可选）。',
              style: AppTextStyles.metaSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条 Prompt 卡片：视觉完全对齐导出页 `_ExportRow`——
/// 22×22 选中指示（橙底白勾 / 浅棕描边，同 `_CheckBox` 规格）、itemTitle 标题、
/// metaSmall 场景说明 / 内容预览、尾部 40×40 图标操作（副本 / 编辑 / 删除）；
/// **整卡点击即选择**；选中态纯背景色（orangeSoft，零位移）。
class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.selected,
    required this.onSelect,
    this.onEdit,
    this.onDelete,
    this.onDuplicate,
  });

  final SummaryPrompt prompt;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// 预置项的「另存为副本」：基于预置内容新建一个可编辑的自定义项。
  /// 预置本身保持只读（作为参考基准），但用户可自由派生。
  final VoidCallback? onDuplicate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 整卡点击切换（含标题/描述区域）；图标按钮自身消费点击。
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 0),
        padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeSoft : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card2),
          boxShadow: AppShadow.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // 选中指示：与导出页 checkbox 同规格（22×22 / 圆角 7 / 橙底白勾）。
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? AppColors.orange : AppColors.card,
                shape: BoxShape.circle,
                border: selected
                    ? null
                    : Border.all(color: AppColors.faint, width: 1.5),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          prompt.name,
                          style: AppTextStyles.itemTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (prompt.builtin) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.orangeWash,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '预置',
                            style: AppTextStyles.metaSmall
                                .copyWith(color: AppColors.orange),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    // 预置项优先显示 catalog 里的场景说明；自定义项显示内容预览。
                    prompt.description.isNotEmpty
                        ? prompt.description
                        : _preview(prompt.content),
                    style: AppTextStyles.metaSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (onDuplicate != null)
              _IconAction(
                icon: Icons.copy_all_outlined,
                tooltip: '另存为副本',
                onTap: onDuplicate!,
              ),
            if (onEdit != null)
              _IconAction(
                icon: Icons.edit_outlined,
                tooltip: '编辑',
                onTap: onEdit!,
              ),
            if (onDelete != null)
              _IconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: '删除',
                onTap: onDelete!,
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

/// 卡片尾部图标操作（40×40 命中区，对齐导出页单条导出图标的规格）。
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: AppColors.muted),
        ),
      ),
    );
  }
}
