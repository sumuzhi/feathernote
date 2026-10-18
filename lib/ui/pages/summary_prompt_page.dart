/// 总结 Prompt 管理页：3 个预置 + 用户自定义，点选即生效（下次总结使用）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/prompts.dart' show kMinutesPromptAsset;
import '../../backend/services/summary_prompts.dart';
import '../theme/app_theme.dart';

/// 总结 Prompt 管理页（压栈页，返回回设置页）。
class SummaryPromptPage extends StatefulWidget {
  /// 构造。
  const SummaryPromptPage({super.key});

  @override
  State<SummaryPromptPage> createState() => _SummaryPromptPageState();
}

class _SummaryPromptPageState extends State<SummaryPromptPage> {
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
    final SummaryPromptStore current =
        _store ?? const SummaryPromptStore();
    final SummaryPromptStore next = current.copyWith(selectedId: prompt.id);
    await saveSummaryPromptStore(next);
    if (!mounted) return;
    setState(() => _store = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「${prompt.name}」已生效——下一次总结时使用')),
    );
  }

  Future<void> _upsertCustom({SummaryPrompt? existing}) async {
    final SummaryPrompt? result = await showDialog<SummaryPrompt>(
      context: context,
      builder: (BuildContext context) =>
          _PromptEditorDialog(existing: existing),
    );
    if (result == null) return;
    final SummaryPromptStore current = _store ?? const SummaryPromptStore();
    final List<SummaryPrompt> customs = <SummaryPrompt>[...current.customs];
    final int idx = customs.indexWhere((SummaryPrompt p) => p.id == result.id);
    if (idx >= 0) {
      customs[idx] = result;
    } else {
      customs.add(result);
    }
    // 新建/编辑后自动选中为下一次总结使用。
    final SummaryPromptStore next = current
        .copyWith(customs: customs, selectedId: result.id);
    await saveSummaryPromptStore(next);
    if (!mounted) return;
    setState(() => _store = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「${result.name}」已保存并设为下次总结使用')),
    );
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
            onPressed: _upsertCustom,
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
                  '选择一个 Prompt，下一次转写总结（含自动生成与手动重新生成）即使用它；'
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
                        prompt.builtin ? null : () => _upsertCustom(existing: prompt),
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

/// 单条 Prompt 卡片：选中态背景色（零位移，同导出页交互语言）。
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
    return Container(
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
              Expanded(
                child: GestureDetector(
                  onTap: onSelect,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color:
                            selected ? AppColors.orange : AppColors.faint,
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
                    ],
                  ),
                ),
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
    );
  }

  static String _preview(String content) {
    final String flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.isEmpty ? '（空模板）' : flat;
  }
}

/// 新建 / 编辑自定义 Prompt 的对话框（名称 + 多行内容）。
class _PromptEditorDialog extends StatefulWidget {
  const _PromptEditorDialog({this.existing});

  final SummaryPrompt? existing;

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _contentCtrl = TextEditingController(text: widget.existing?.content ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameCtrl.text.trim();
    final String content = _contentCtrl.text;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写 Prompt 名称')),
      );
      return;
    }
    if (!content.contains('{{meeting_content}}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模板必须包含 {{meeting_content}} 占位符（逐字稿注入点）')),
      );
      return;
    }
    Navigator.of(context).pop(
      SummaryPrompt(
        id: widget.existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        content: content,
        builtin: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '编辑 Prompt' : '新建 Prompt'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _nameCtrl,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：周会要点、客户访谈',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '模板内容（必须包含 {{meeting_content}}）',
              style: AppTextStyles.metaSmall,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 220,
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(20000),
                ],
                decoration: const InputDecoration(
                  hintText: '写下你希望 AI 按什么结构总结逐字稿…\n\n'
                      '例：请总结出待办清单，格式：\n# 待办\n| 事项 | 负责人 | 期限 |\n\n'
                      '【逐字稿】\n{{meeting_content}}',
                  border: OutlineInputBorder(),
                ),
                style: AppTextStyles.metaSmall,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text(editing ? '保存' : '创建'),
        ),
      ],
    );
  }
}
