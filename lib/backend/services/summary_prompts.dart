/// 总结 Prompt 管理：预置 3 个 + 用户自定义 N 个，任选其一生效。
///
/// 语义（用户要求）：**选择只在「下一次总结」生效**——每次生成都从持久化
/// 存储读取当前选中的 Prompt，读取动作发生在生成启动时；生成进行中换选
/// 不影响该次生成（模板已在启动瞬间捕获）。强制重新生成也按当下选择。
///
/// 持久化：应用文档目录 `summary_prompts.json`（沿用本项目「不引入
/// shared_preferences」的惯例，见 export_destination.dart）。文件只存
/// **用户自定义项与选中 id**；3 个预置项由代码常量定义（升级随 App 演进，
/// 不会被旧文件快照钉死）：
/// - `builtin-current`   标准会议纪要（内容 = assets/prompts/minutes.md，
///   即既有 knowledge-extract 模板，运行时从资产加载）；
/// - `builtin-interview` 面试复盘；
/// - `builtin-chat`      日常聊天回顾。
///
/// 模板占位符与既有插值器一致：`{{meeting_content}}`（必需）、
/// `{{meeting_title}}` / `{{meeting_date}}` / `{{duration}}` /
/// `{{speaker_count}}` / `{{speaker_roster}}` / `{{transcript}}`（可选）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'prompts.dart';

/// 一条总结 Prompt。
class SummaryPrompt {
  /// 构造。
  const SummaryPrompt({
    required this.id,
    required this.name,
    required this.content,
    required this.builtin,
  });

  /// 从 JSON 反序列化。
  factory SummaryPrompt.fromJson(Map<String, dynamic> json) => SummaryPrompt(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名',
    content: json['content'] as String? ?? '',
    builtin: json['builtin'] as bool? ?? false,
  );

  /// 标准会议纪要（既有模板，运行时从资产解析）。
  static const String builtinCurrentId = 'builtin-current';

  /// 面试复盘预置 id。
  static const String builtinInterviewId = 'builtin-interview';

  /// 日常聊天预置 id。
  static const String builtinChatId = 'builtin-chat';

  /// 唯一标识（预置为固定 id；自定义 `custom-<uuid>`）。
  final String id;

  /// 显示名。
  final String name;

  /// 模板内容（含 `{{meeting_content}}` 占位符）。
  final String content;

  /// 是否预置（预置不可编辑/删除）。
  final bool builtin;

  /// 序列化。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'content': content,
    'builtin': builtin,
  };

  /// 复制。
  SummaryPrompt copyWith({String? name, String? content}) => SummaryPrompt(
    id: id,
    name: name ?? this.name,
    content: content ?? this.content,
    builtin: builtin,
  );
}

/// 面试复盘预置模板（用户要求：总结问过的问题、没答出来的问题等，帮助复盘）。
const String kBuiltinInterviewTemplate = '''
你将收到一场面试的完整逐字稿。请以帮候选人**复盘**为目的，严格输出以下 Markdown 结构：

# 面试复盘

## 一、面试概况
- 时间、时长、参与人数（据逐字稿判断；判断不出的写「未可知」）

## 二、面试官提问清单
按提问顺序制表：
| # | 问题 | 我的回答概述 | 回答质量（✅ 流畅 / ⚠️ 勉强 / ❌ 未答上） |

## 三、未答上 / 答得不理想的问题（重点复盘）
逐条展开，**一条不许漏**：
- **问题原文**（保留面试官原话）
- **考察意图**：这题在考什么
- **薄弱点分析**：我的缺口在哪里
- **参考答案要点**：给出简洁、可背诵的答题框架（3-5 条要点）

## 四、亮点与加分项
哪些回答表现好、好在哪（可复用的表达方式或答题结构）

## 五、改进行动计划
3-5 条可执行的下一步（要补的知识点、要准备的答案、要打磨的表达）

要求：所有结论必须以逐字稿为据，引用时保留口语证据；未答上的问题宁可标注「未答上」也不许臆测我的回答。

【逐字稿与会议信息】
{{meeting_content}}
''';

/// 日常聊天回顾预置模板（用户要求：普通日常聊天总结）。
const String kBuiltinChatTemplate = '''
你将收到一段日常聊天的完整逐字稿。请输出一份轻松易读的聊天回顾，严格使用以下 Markdown 结构：

# 聊天回顾

## 一、这场聊了什么
3-5 句话概括主要话题与整体氛围。

## 二、话题清单
按出现顺序制表（5-10 条为宜）：
| 话题 | 谁提起 | 聊到的要点 |

## 三、值得记住的事
- **约定 / 待办**：谁答应做什么、时间点（没有写「无」）
- **金句 / 段子**：原话摘录 1-3 条
- **提到的人名 / 地点 / 事件**：未来可能再提及的信息

## 四、下次可以聊的
基于本次话题列出 2-3 个可延续的线头。

要求：语气轻松、忠实原意、不过度解读；逐字稿里没有的内容不要编造。

【逐字稿与会议信息】
{{meeting_content}}
''';

/// 3 个预置项（顺序即默认展示顺序；`builtin-current` 内容运行时从资产解析）。
List<SummaryPrompt> builtinPrompts() => <SummaryPrompt>[
  const SummaryPrompt(
    id: SummaryPrompt.builtinCurrentId,
    name: '标准会议纪要',
    content: '', // 内容 = assets/prompts/minutes.md，运行时经 loadMinutesTemplate() 解析
    builtin: true,
  ),
  const SummaryPrompt(
    id: SummaryPrompt.builtinInterviewId,
    name: '面试复盘',
    content: kBuiltinInterviewTemplate,
    builtin: true,
  ),
  const SummaryPrompt(
    id: SummaryPrompt.builtinChatId,
    name: '日常聊天回顾',
    content: kBuiltinChatTemplate,
    builtin: true,
  ),
];

const String _kFileName = 'summary_prompts.json';

/// 存储文件路径（应用文档目录）。
Future<String> _storePath() async {
  final Directory base = await getApplicationDocumentsDirectory();
  return p.join(base.path, _kFileName);
}

/// 持久化快照：用户自定义项 + 选中 id。
class SummaryPromptStore {
  /// 构造。
  const SummaryPromptStore({
    this.selectedId = SummaryPrompt.builtinCurrentId,
    this.customs = const <SummaryPrompt>[],
  });

  /// 从 JSON 反序列化（损坏/缺字段时回落默认；拒绝持久化预置项快照）。
  factory SummaryPromptStore.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = json['customs'] as List<dynamic>? ?? const <dynamic>[];
    return SummaryPromptStore(
      selectedId: json['selectedId'] as String? ?? SummaryPrompt.builtinCurrentId,
      customs: raw
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> e) => SummaryPrompt.fromJson(e))
          .where(
            (SummaryPrompt p) =>
                !p.builtin &&
                p.id.isNotEmpty &&
                p.name.isNotEmpty &&
                p.id.startsWith('custom-'),
          )
          .toList(growable: false),
    );
  }

  /// 当前选中 id（指向已删除项时由 [effectiveSelection] 回落）。
  final String selectedId;

  /// 用户自定义项。
  final List<SummaryPrompt> customs;

  /// 序列化。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'selectedId': selectedId,
    'customs': <Map<String, dynamic>>[
      for (final SummaryPrompt p in customs) p.toJson(),
    ],
  };

  /// 全量列表：3 个预置在前 + 自定义（按创建顺序）。
  List<SummaryPrompt> allPrompts() => <SummaryPrompt>[...builtinPrompts(), ...customs];

  /// 解析选中项（selectedId 失效时回落到标准会议纪要）。
  SummaryPrompt effectiveSelection() {
    for (final SummaryPrompt p in allPrompts()) {
      if (p.id == selectedId) return p;
    }
    return builtinPrompts().first;
  }

  /// 复制。
  SummaryPromptStore copyWith({String? selectedId, List<SummaryPrompt>? customs}) =>
      SummaryPromptStore(
        selectedId: selectedId ?? this.selectedId,
        customs: customs ?? this.customs,
      );
}

/// 读取存储（文件不存在/损坏 → 默认存储）。
Future<SummaryPromptStore> loadSummaryPromptStore() async {
  try {
    final File file = File(await _storePath());
    if (!file.existsSync()) return const SummaryPromptStore();
    final dynamic decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return const SummaryPromptStore();
    return SummaryPromptStore.fromJson(decoded);
  } catch (_) {
    return const SummaryPromptStore();
  }
}

/// 保存存储（原子写：先写临时文件再 rename）。
Future<void> saveSummaryPromptStore(SummaryPromptStore store) async {
  final String path = await _storePath();
  final File tmp = File('$path.tmp');
  await tmp.writeAsString(jsonEncode(store.toJson()), flush: true);
  try {
    await tmp.rename(path);
  } on FileSystemException {
    // rename 失败（个别 ROM 不允许覆盖）→ 直接覆盖写兜底。
    await File(path).writeAsString(jsonEncode(store.toJson()), flush: true);
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

/// 解析某条 Prompt 的实际模板内容（`builtin-current` 从资产加载并缓存）。
Future<String> resolveTemplateOf(SummaryPrompt prompt) async {
  if (prompt.id == SummaryPrompt.builtinCurrentId) {
    return loadMinutesTemplate();
  }
  return prompt.content;
}

/// 生成启动时调用：读取当前选中的 Prompt。
///
/// 返回 (名称, 模板内容)。**`builtin-current` 的模板内容恒返回 null**——
/// 表示走 buildMinutesMessages 的默认资产模板路径（含其专属 system 消息）。
Future<(String name, String? templateOverride)> loadSelectedPrompt() async {
  final SummaryPromptStore store = await loadSummaryPromptStore();
  final SummaryPrompt selection = store.effectiveSelection();
  if (selection.id == SummaryPrompt.builtinCurrentId) {
    return (selection.name, null);
  }
  return (selection.name, await resolveTemplateOf(selection));
}
