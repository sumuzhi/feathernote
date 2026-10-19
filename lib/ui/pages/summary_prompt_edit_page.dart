/// 总结 Prompt 编辑页（路由页；设计语言对齐「数据库」导出页）。
///
/// 布局（用户要求）：
/// - **编辑区默认撑满**：内容输入框用 `Expanded` 占满 header 与保存按钮之间的
///   全部空间（文字多时框内自行滚动）；
/// - **创建按钮固定在最底部**：不随内容滚动；
/// - **键盘适配**：整列以 `viewInsets.bottom` 垫底——输入法弹出时可用高度收窄，
///   编辑区（Expanded）随之收缩、按钮始终浮在键盘上沿可见；
/// - **header 与 content 保持间距**：顶栏下方 8px。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/services/summary_prompts.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';

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
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // 固定头部：顶栏（返回 + 标题/副标题）。
            AppTopBar(
              title: _editing ? '编辑 Prompt' : '新建 Prompt',
              subtitle: _editing ? '保存后自动设为下次总结使用' : '创建后自动设为下次总结使用',
              leadingIcon: Icons.chevron_left_rounded,
              onLeading: () => context.pop(),
            ),
            // header 与 content 保持一点距离（用户要求）。
            const SizedBox(height: 8),
            // 主体：以键盘高度垫底——输入法弹出时可用高度收窄、编辑区收缩，
            // 保存按钮始终浮在键盘上沿（用户要求：注意输入法弹窗位置）。
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('名称', style: AppTextStyles.settingTitle),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameCtrl,
                        maxLength: 20,
                        buildCounter: (
                          BuildContext context, {
                          required int currentLength,
                          required int? maxLength,
                          required bool isFocused,
                        }) =>
                            null, // 隐藏字数角标（上限短到无需提示，保持视觉干净）
                        cursorColor: AppColors.orange,
                        style: AppTextStyles.body15,
                        decoration: _inputDecoration('如：周会要点、客户访谈'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '模板内容（必须包含 {{meeting_content}} 占位符）',
                        style: AppTextStyles.settingTitle,
                      ),
                      const SizedBox(height: 8),
                      // 编辑区默认撑满剩余空间（用户要求）；文字多时框内自行滚动。
                      Expanded(
                        child: TextField(
                          controller: _contentCtrl,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          textAlignVertical: TextAlignVertical.top,
                          cursorColor: AppColors.orange,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(20000),
                          ],
                          style: AppTextStyles.metaSmall.copyWith(height: 1.5),
                          decoration: _inputDecoration(
                            '写下你希望 AI 按什么结构总结逐字稿…\n\n'
                            '例：请总结出待办清单，格式：\n# 待办\n| 事项 | 负责人 | 期限 |\n\n'
                            '【逐字稿】\n{{meeting_content}}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '可选占位符：{{meeting_title}} / {{meeting_date}} / {{duration}} / '
                        '{{speaker_count}} / {{speaker_roster}} / {{transcript}}',
                        style: AppTextStyles.metaSmall,
                      ),
                      const SizedBox(height: 14),
                      // 创建/保存按钮固定在最底部（用户要求）。
                      Opacity(
                        opacity: _saving ? 0.6 : 1,
                        child: AppPillButton(
                          label: _saving ? '保存中…' : (_editing ? '保存' : '创建'),
                          onTap: _saving ? () {} : _submit,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
            // 底部安全区（键盘垫底已在上方 Expanded 内处理，这里只管手势条）。
            SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
          ],
        ),
      ),
    );
  }

  /// App 风格输入装饰：白底卡片 + 浅棕描边 + 小卡片圆角（对齐卡片语言）。
  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.metaSmall,
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.line, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.orange, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.line, width: 1.2),
      ),
    );
  }
}
