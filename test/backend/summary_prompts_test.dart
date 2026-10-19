// 总结 Prompt 管理的存储、选择与模板库单测。
//
// 覆盖用户需求的关键语义：
// - 模板库由 assets/prompts/catalog.json 驱动，预置项只读；
// - 预置项带 description（列表页用于说明场景）；
// - 自定义 N 个（增改删），持久化往返一致；
// - 选中项指向被删除的自定义项时回落到 catalog 首项（标准会议纪要）；
// - 所有模板（含 builtin-current）都从资产解析出正文；
// - 自定义模板经 interpolate 正确插值 {{meeting_content}}。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:smart_minutes_flutter/backend/engine/engine.dart';
import 'package:smart_minutes_flutter/backend/services/prompts.dart';
import 'package:smart_minutes_flutter/backend/services/summary_prompts.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String basePath;
  _FakePathProvider(this.basePath);

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

/// 用真实资产文件内容替换 rootBundle，避免单测依赖 Flutter asset 打包。
///
/// 直接读磁盘上的 assets/prompts/ 目录（测试工作目录是项目根），
/// 这样单测验证的就是**真实模板**，而非另写一份假模板。
///
/// ⚠️ 注意返回类型：`flutter/assets` 通道的返回值必须经 StandardMessageCodec
/// 编码。`loadString` 期望 String（或 Uint8List，内部会 decode）。
/// 直接返回 null 表示「资产不存在」（loadString 会抛异常，符合预期）。
void _installAssetLoader() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      final String key = const StringCodec().decodeMessage(message)!;
      final File file = File(key);
      if (!file.existsSync()) {
        return null; // 资产不存在
      }
      final Uint8List bytes = file.readAsBytesSync();
      return const StringCodec().encodeMessage(utf8.decode(bytes));
    },
  );
}

Meeting _meeting() => Meeting(
  id: 'm1',
  title: '后端二面',
  createdAt: DateTime(2026, 10, 18, 14, 30),
  durationMs: 60000,
  sampleRate: 16000,
  speakerCount: 1,
  status: MeetingStatus.stopped,
  source: MeetingSource.microphone,
  finalizeStatus: FinalizeStatus.done,
  transcriptSource: TranscriptSource.realtime,
  audioStatus: AudioStatus.done,
  audioBytes: 64000,
  minutesPartial: false,
  speakers: const <Speaker>[
    Speaker(
      meetingId: 'm1',
      speakerId: 'spk_1',
      name: '面试官',
      colorIndex: 0,
      firstSeenMs: 0,
    ),
  ],
  segments: <TranscriptSegment>[
    TranscriptSegment(
      meetingId: 'm1',
      segmentId: 's1',
      ordinal: 0,
      speakerId: 'spk_1',
      text: '请讲讲数据库索引的原理',
      startTime: 0,
      endTime: 5000,
      confidence: 0.99,
      seqStart: 0,
      seqEnd: 1600,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('summary_prompts_test');
    PathProviderPlatform.instance = _FakePathProvider(base.path);
    clearPromptCaches();
    clearMinutesTemplateCache();
    _installAssetLoader();
  });

  tearDown(() async {
    await base.delete(recursive: true);
  });

  group('模板库（catalog.json 驱动）', () {
    test('catalog 解析出 6 个预置，顺序正确，均带 description', () async {
      final List<SummaryPrompt> prompts = await builtinPromptsAsync();
      expect(prompts.length, 6);
      expect(
        prompts.map((SummaryPrompt p) => p.name).toList(),
        <String>[
          '标准会议纪要',
          '知识萃取',
          '面试复盘',
          '日常聊天回顾',
          '客户访谈',
          '一对一沟通',
        ],
      );
      // 每个预置都必须有场景说明（列表页用来帮助用户选择）。
      for (final SummaryPrompt p in prompts) {
        expect(p.builtin, isTrue);
        expect(p.description.trim(), isNotEmpty, reason: '${p.name} 缺少 description');
      }
    });

    test('catalog.json 本身合法且字段齐全', () async {
      final String raw = await File('assets/prompts/catalog.json').readAsString();
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic> items = json['prompts'] as List<dynamic>;
      expect(items.length, 6);
      for (final dynamic item in items) {
        final Map<String, dynamic> m = item as Map<String, dynamic>;
        expect(m['id'], isA<String>());
        expect(m['name'], isA<String>());
        expect(m['description'], isA<String>());
        expect(m['file'], isA<String>());
        // file 指向的模板必须真实存在。
        expect(
          File('assets/prompts/${m['file']}').existsSync(),
          isTrue,
          reason: '模板文件缺失：${m['file']}',
        );
      }
    });

    test('每个预置模板都能解析出正文且含必需占位符', () async {
      final List<SummaryPrompt> prompts = await builtinPromptsAsync();
      for (final SummaryPrompt p in prompts) {
        final String body = await resolveTemplateOf(p);
        expect(body.trim(), isNotEmpty, reason: '${p.name} 正文为空');
        expect(
          body,
          contains('{{meeting_content}}'),
          reason: '${p.name} 缺少 {{meeting_content}} 占位符',
        );
      }
    });

    test('面试复盘模板覆盖关键结构', () async {
      final List<SummaryPrompt> prompts = await builtinPromptsAsync();
      final SummaryPrompt interview = prompts.firstWhere(
        (SummaryPrompt p) => p.id == SummaryPrompt.builtinInterviewId,
      );
      final String body = await resolveTemplateOf(interview);
      expect(body, contains('提问清单'));
      expect(body, contains('未答上'));
      expect(body, contains('改进行动计划'));
    });

    test('标准会议纪要已重写为通用纪要（不再是知识萃取）', () async {
      final List<SummaryPrompt> prompts = await builtinPromptsAsync();
      final SummaryPrompt standard = prompts.firstWhere(
        (SummaryPrompt p) => p.id == SummaryPrompt.builtinCurrentId,
      );
      final String body = await resolveTemplateOf(standard);
      // 通用纪要标志性章节
      expect(body, contains('待办事项'));
      expect(body, contains('决议事项'));
      // 不应再是知识萃取那套
      expect(body, isNot(contains('知识萃取')));
      expect(body, isNot(contains('经验萃取顾问')));
    });
  });

  group('SummaryPromptStore 选择与持久化', () {
    test('默认存储：选中标准会议纪要', () {
      const SummaryPromptStore store = SummaryPromptStore();
      expect(store.selectedId, SummaryPrompt.builtinCurrentId);
      expect(store.customs, isEmpty);
    });

    test('自定义项经 JSON 往返保持一致；损坏 JSON 回落默认', () async {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-1',
        name: '待办清单',
        content: '# 待办\n{{meeting_content}}',
        builtin: false,
      );
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: 'custom-1', customs: <SummaryPrompt>[custom]),
      );

      final SummaryPromptStore loaded = await loadSummaryPromptStore();
      expect(loaded.selectedId, 'custom-1');
      expect(loaded.customs.single.name, '待办清单');
      expect(loaded.customs.single.content, contains('{{meeting_content}}'));

      // 写入损坏内容 → 回落默认。
      await File(
        '${base.path}${Platform.pathSeparator}summary_prompts.json',
      ).writeAsString('{broken json');
      final SummaryPromptStore fallback = await loadSummaryPromptStore();
      expect(fallback.selectedId, SummaryPrompt.builtinCurrentId);
      expect(fallback.customs, isEmpty);
    });

    test('选中项被删除 → 回落标准会议纪要（effectiveSelection）', () async {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-9',
        name: 'x',
        content: 'c {{meeting_content}}',
        builtin: false,
      );
      final SummaryPromptStore withCustom = const SummaryPromptStore(
        customs: <SummaryPrompt>[custom],
      ).copyWith(selectedId: 'custom-9');
      expect((await withCustom.effectiveSelection()).id, 'custom-9');

      // 删除后：store 仍持有失效 selectedId → 回落 catalog 首项。
      final SummaryPromptStore afterDelete = withCustom.copyWith(
        customs: <SummaryPrompt>[],
      );
      expect((await afterDelete.effectiveSelection()).id, SummaryPrompt.builtinCurrentId);
    });

    test('fromJson 拒绝持久化的预置项快照与非法条目', () {
      final SummaryPromptStore store = SummaryPromptStore.fromJson(
        <String, dynamic>{
          'selectedId': 'builtin-interview',
          'customs': <dynamic>[
            <String, dynamic>{
              'id': 'builtin-current',
              'name': '冒充预置',
              'content': 'x',
              'builtin': true,
            },
            <String, dynamic>{'id': 'custom-ok', 'name': '好的', 'content': 'c'},
            <String, dynamic>{'id': '', 'name': '空 id', 'content': 'c'},
          ],
        },
      );
      expect(store.customs.length, 1);
      expect(store.customs.single.id, 'custom-ok');
    });

    test('自定义项可携带 description（另存为副本时不被丢弃）', () {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-3',
        name: '副本',
        content: 'c {{meeting_content}}',
        builtin: false,
        description: '我的说明',
      );
      final SummaryPrompt round = SummaryPrompt.fromJson(custom.toJson());
      expect(round.description, '我的说明');
    });
  });

  group('生成接线（loadSelectedPrompt / buildMinutesMessages）', () {
    test('默认选中 → 返回真实模板正文（不再是 null override）', () async {
      final (String name, String template) = await loadSelectedPrompt();
      expect(name, '标准会议纪要');
      expect(template.trim(), isNotEmpty);
      expect(template, contains('{{meeting_content}}'));
      // 新模板应含通用纪要章节。
      expect(template, contains('待办事项'));
    });

    test('选中自定义 → 插值注入逐字稿', () async {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-2',
        name: '要点提炼',
        content: '要点提炼任务：\n{{meeting_content}}',
        builtin: false,
      );
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: 'custom-2', customs: <SummaryPrompt>[custom]),
      );
      final (String name, String template) = await loadSelectedPrompt();
      expect(name, '要点提炼');
      expect(template, contains('要点提炼任务'));

      final List<LlmMessage> messages = await buildMinutesMessages(
        _meeting(),
        templateOverride: template,
      );
      expect(messages.length, 2);
      expect(messages[0].content, contains('记录整理助手'));
      expect(messages[1].content, contains('数据库索引的原理'));
      expect(messages[1].content, contains('要点提炼任务'));
      expect(messages[1].content, isNot(contains('{{meeting_content}}')));
    });

    test('选中预置「知识萃取」→ 消息里是知识萃取的正文（不是默认模板）', () async {
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: SummaryPrompt.builtinKnowledgeId),
      );
      final (String name, String template) = await loadSelectedPrompt();
      expect(name, '知识萃取');

      // ① 返回的模板必须是知识萃取正文，不能是标准纪要正文。
      expect(template, contains('经验萃取顾问'));
      expect(template, isNot(contains('决议事项')));

      final List<LlmMessage> messages = await buildMinutesMessages(
        _meeting(),
        templateOverride: template,
      );
      final String userMessage = messages[1].content;

      // ② user 消息必须包含知识萃取模板的特征文本 —— 这是「模板真的生效」的
      //    决定性证据：只有模板正文被插值进来，才会出现这些字。
      expect(userMessage, contains('提炼而非复述'), reason: '知识萃取的 Working Principles 未进入 prompt');
      expect(userMessage, contains('经验萃取'));

      // ③ 不能混入标准会议纪要的章节（否则说明用错了模板）。
      expect(userMessage, isNot(contains('决议事项')));
      expect(userMessage, isNot(contains('待办事项')));

      // ④ 逐字稿已注入。
      expect(userMessage, contains('数据库索引的原理'));
      expect(userMessage, isNot(contains('{{meeting_content}}')));
    });

    test('切模板后重新生成，prompt 内容随之改变', () async {
      // 先选标准会议纪要。
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: SummaryPrompt.builtinCurrentId),
      );
      final (String name1, String tpl1) = await loadSelectedPrompt();
      final List<LlmMessage> m1 = await buildMinutesMessages(
        _meeting(),
        templateOverride: tpl1,
      );

      // 再切到客户访谈。
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: SummaryPrompt.builtinCustomerInterviewId),
      );
      final (String name2, String tpl2) = await loadSelectedPrompt();
      final List<LlmMessage> m2 = await buildMinutesMessages(
        _meeting(),
        templateOverride: tpl2,
      );

      expect(name1, '标准会议纪要');
      expect(name2, '客户访谈');
      // 两次的 user 消息必须不同 —— 证明换模板确实换了 prompt。
      expect(m1[1].content, isNot(equals(m2[1].content)));
      // 客户访谈的特征章节。
      expect(m2[1].content, contains('痛点与诉求'));
      expect(m2[1].content, contains('隐含需求'));
      expect(m1[1].content, isNot(contains('痛点与诉求')));
    });
  });
}
