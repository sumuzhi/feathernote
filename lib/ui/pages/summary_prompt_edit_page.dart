/// 总结 Prompt 编辑页（路由页，用户要求：弹窗操作区域太小）。
///
/// 键盘适配：内容包在 [SingleChildScrollView] 里 + 底部 `viewInsets` 垫底，
/// 输入法弹出时**内容区滚动**而不是把保存按钮顶出去造成溢出。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/summary_prompts.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// 全页编辑器。`extra` 传 [SummaryPrompt]（编辑既有项）；null = 新建。
class SummaryPromptEditPage extends ConsumerStatefulWidget {
  /// 构造。
  const SummaryPromptEditPage({super.key, this.existing});

  /// 编辑目标（null = 新建）。
  final SummaryPrompt? existing;

  @override
  ConsumerState<SummaryPromptEditPage> createState() =>
      _SummaryPromptEditPageState();
}

class _SummaryPromptEditPageState extends ConsumerState<SummaryPromptEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;
  bool _saving = false;

  bool get _editing => widget.existing != null;

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

  Future<void> _submit() async {
    final String name = _nameCtrl.text.trim();
    final String content = _contentCtrl.text;
    if (name.isEmpty) {
      ref.read(toastProvider.notifier).show('请填写 Prompt 名称', tone: ToastTone.warning);
      return;
    }
    if (!content.contains('{{meeting_content}}')) {
      ref.read(toastProvider.notifier).show(
            '模板必须包含 {{meeting_content}} 占位符（逐字稿注入点）',
            tone: ToastTone.warning,
          );
      return;
    }
    setState(() => _saving = true);
    final SummaryPromptStore store = await loadSummaryPromptStore();
    final SummaryPrompt result = SummaryPrompt(
      id: widget.existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      content: content,
      builtin: false,
    );
    final List<SummaryPrompt> customs = <SummaryPrompt>[...store.customs];
    final int idx = customs.indexWhere((SummaryPrompt p) => p.id == result.id);
    if (idx >= 0) {
      customs[idx] = result;
    } else {
      customs.add(result);
    }
    // 新建/编辑后自动选中为下一次总结使用。
    await saveSummaryPromptStore(
      store.copyWith(customs: customs, selectedId: result.id),
    );
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(
          '「${result.name}」已保存并设为下次总结使用',
          tone: ToastTone.success,
        );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => context.pop(),
        ),
        title: Text(_editing ? '编辑 Prompt' : '新建 Prompt', style: AppTextStyles.subHead),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              // 键盘弹出时整体滚动（bottom inset 垫底），不压缩出不溢出的死区。
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _nameCtrl,
                      maxLength: 20,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '如：周会要点、客户访谈',
                      ),
                      style: AppTextStyles.body15,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '模板内容（必须包含 {{meeting_content}} 占位符）',
                      style: AppTextStyles.metaSmall,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _contentCtrl,
                      maxLines: null,
                      minLines: 14,
                      keyboardType: TextInputType.multiline,
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
                    const SizedBox(height: 8),
                    Text(
                      '可选占位符：{{meeting_title}} / {{meeting_date}} / {{duration}} / '
                      '{{speaker_count}} / {{speaker_roster}} / {{transcript}}',
                      style: AppTextStyles.metaSmall,
                    ),
                  ],
                ),
              ),
            ),
            // 保存按钮固定底部：键盘弹出时随 SafeArea 上移，内容区滚动消化。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_editing ? '保存' : '创建', style: AppTextStyles.settingTitle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
