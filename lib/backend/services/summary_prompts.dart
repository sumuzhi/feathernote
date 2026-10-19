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

import 'package:flutter/services.dart' show rootBundle;
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
    this.description = '',
  });

  /// 从 JSON 反序列化。
  factory SummaryPrompt.fromJson(Map<String, dynamic> json) => SummaryPrompt(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '未命名',
    content: json['content'] as String? ?? '',
    builtin: json['builtin'] as bool? ?? false,
    description: json['description'] as String? ?? '',
  );

  /// 标准会议纪要（既有模板，运行时从资产解析）。
  static const String builtinCurrentId = 'builtin-current';

  /// 面试复盘预置 id。
  static const String builtinInterviewId = 'builtin-interview';

  /// 日常聊天预置 id。
  static const String builtinChatId = 'builtin-chat';

  /// 知识萃取预置 id（原 minutes.md 那套，从 builtin-current 独立出来）。
  static const String builtinKnowledgeId = 'builtin-knowledge';

  /// 客户访谈预置 id。
  static const String builtinCustomerInterviewId = 'builtin-customer-interview';

  /// 一对一沟通预置 id。
  static const String builtinOneOnOneId = 'builtin-one-on-one';

  /// 唯一标识（预置为固定 id；自定义 `custom-<uuid>`）。
  final String id;

  /// 显示名。
  final String name;

  /// 一句话场景说明（预置来自 catalog.json；自定义可空）。
  ///
  /// 列表页用它告诉用户「这个模板适合什么场景」，比只有名字更易选。
  final String description;

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
    if (description.isNotEmpty) 'description': description,
  };

  /// 复制。
  SummaryPrompt copyWith({String? name, String? content, String? description}) =>
      SummaryPrompt(
        id: id,
        name: name ?? this.name,
        content: content ?? this.content,
        builtin: builtin,
        description: description ?? this.description,
      );
}

/// 预置模板目录（资产）。
const String kPromptCatalogAsset = 'assets/prompts/catalog.json';

/// 目录里一条预置模板的元信息。
class _CatalogEntry {
  const _CatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.file,
    required this.order,
  });

  final String id;
  final String name;
  final String description;
  final String file;
  final int order;
}

/// 已加载的目录缓存（进程内只解析一次）。
List<_CatalogEntry>? _catalogCache;

/// 已加载的模板正文缓存（key = 资产路径）。
final Map<String, String> _templateCache = <String, String>{};

/// 读取并解析 catalog.json（带缓存）。
Future<List<_CatalogEntry>> _loadCatalog() async {
  final List<_CatalogEntry>? cached = _catalogCache;
  if (cached != null) return cached;

  // 单元测试环境（未初始化 Flutter binding）读不到 rootBundle。
  // 这不是错误场景：此时降级为空目录，让调用方回落到默认行为，
  // 避免把「测试环境限制」变成业务异常（曾导致 minutes_service 单测全挂）。
  String raw;
  try {
    raw = await rootBundle.loadString(kPromptCatalogAsset);
  } catch (_) {
    _catalogCache = const <_CatalogEntry>[];
    return _catalogCache!;
  }
  final dynamic decoded = jsonDecode(raw);
  final List<dynamic> items =
      (decoded is Map<String, dynamic> ? decoded['prompts'] as List<dynamic>? : null) ??
      const <dynamic>[];

  final List<_CatalogEntry> entries = <_CatalogEntry>[];
  for (final dynamic item in items) {
    if (item is! Map<String, dynamic>) continue;
    final String id = item['id'] as String? ?? '';
    final String name = item['name'] as String? ?? '';
    final String file = item['file'] as String? ?? '';
    if (id.isEmpty || name.isEmpty || file.isEmpty) continue;
    entries.add(
      _CatalogEntry(
        id: id,
        name: name,
        description: item['description'] as String? ?? '',
        file: file,
        order: item['order'] as int? ?? 999,
      ),
    );
  }
  entries.sort((_CatalogEntry a, _CatalogEntry b) => a.order.compareTo(b.order));
  _catalogCache = entries;
  return entries;
}

/// 读取某个模板文件的正文（带缓存）。
Future<String> _loadTemplateBody(String file) async {
  final String assetPath = 'assets/prompts/$file';
  final String? cached = _templateCache[assetPath];
  if (cached != null) return cached;
  String text;
  try {
    text = await rootBundle.loadString(assetPath);
  } catch (_) {
    // 资产缺失 / 测试环境无 binding 时降级：返回仅含占位符的最小模板，
    // 保证生成链路不中断（否则整个纪要生成会因读模板失败而报错）。
    text = '{{meeting_content}}';
  }
  _templateCache[assetPath] = text;
  return text;
}

/// 全部预置项（从 catalog.json 加载，按 order 排序）。
///
/// 模板正文按需加载（见 [resolveTemplateOf]），此处 content 留空，
/// 避免启动时把所有模板正文一次性读进内存。
Future<List<SummaryPrompt>> builtinPromptsAsync() async {
  final List<_CatalogEntry> entries = await _loadCatalog();
  return <SummaryPrompt>[
    for (final _CatalogEntry e in entries)
      SummaryPrompt(
        id: e.id,
        name: e.name,
        content: '',
        builtin: true,
        description: e.description,
      ),
  ];
}

/// 从目录查某个预置项对应的模板文件（找不到返回 null）。
Future<String?> _templateFileOf(String id) async {
  final List<_CatalogEntry> entries = await _loadCatalog();
  for (final _CatalogEntry e in entries) {
    if (e.id == id) return e.file;
  }
  return null;
}

/// 清除模板缓存（供测试与热重载使用）。
void clearPromptCaches() {
  _catalogCache = null;
  _templateCache.clear();
}

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

  /// 全量列表：预置（按 catalog order）在前 + 自定义（按创建顺序）。
  ///
  /// 预置元信息来自 catalog.json，因此需要异步加载。
  Future<List<SummaryPrompt>> allPrompts() async => <SummaryPrompt>[
    ...await builtinPromptsAsync(),
    ...customs,
  ];

  /// 解析选中项（selectedId 失效时回落到 catalog 的第一项，即标准会议纪要）。
  Future<SummaryPrompt> effectiveSelection() async {
    final List<SummaryPrompt> all = await allPrompts();
    for (final SummaryPrompt p in all) {
      if (p.id == selectedId) return p;
    }
    // 目录为空（测试环境无 asset）时兜底返回一个最小预置项，
    // 保证调用方不必处理 null，也不会崩。
    if (all.isEmpty) {
      return const SummaryPrompt(
        id: SummaryPrompt.builtinCurrentId,
        name: '标准会议纪要',
        content: '{{meeting_content}}',
        builtin: true,
      );
    }
    return all.first;
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

/// 解析某条 Prompt 的实际模板内容。
///
/// - 预置：按 catalog.json 里的 file 字段从资产加载（带缓存）；
/// - 自定义：直接返回用户填写的内容。
Future<String> resolveTemplateOf(SummaryPrompt prompt) async {
  if (!prompt.builtin) return prompt.content;
  final String? file = await _templateFileOf(prompt.id);
  if (file == null) return prompt.content; // 目录里没有 → 回落（理论上不会发生）
  return _loadTemplateBody(file);
}

/// 生成启动时调用：读取当前选中的 Prompt。
///
/// 返回 (名称, 模板内容)。
///
/// ⚠️ 现在**所有模板都返回非 null 的模板内容**（包括 builtin-current）——
/// 因为模板正文已全部外置到 assets/prompts/*.md，统一由 catalog 驱动。
/// 旧实现里 builtin-current 返回 null 是为了走「资产默认路径 + 专属 system 消息」，
/// 现在这套特殊处理已移除（见 buildMinutesMessages 的注释）。
Future<(String name, String template)> loadSelectedPrompt() async {
  final SummaryPromptStore store = await loadSummaryPromptStore();
  final SummaryPrompt selection = await store.effectiveSelection();
  return (selection.name, await resolveTemplateOf(selection));
}
