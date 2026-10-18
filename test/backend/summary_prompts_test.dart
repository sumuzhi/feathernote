// 总结 Prompt 管理的存储与选择逻辑单测（fake path_provider，纯文件 IO）。
//
// 覆盖用户需求的关键语义：
// - 预置 3 个（标准纪要 / 面试复盘 / 日常聊天），不可编辑删除；
// - 自定义 N 个（增改删），持久化往返一致；
// - 选中项指向被删除的自定义项时回落到标准会议纪要；
// - builtin-current 的模板运行时从资产解析（loadSelectedPrompt 返回 null override）；
// - 自定义模板经 interpolate 正确插值 {{meeting_content}}。
import 'dart:io';

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
  });

  tearDown(() async {
    await base.delete(recursive: true);
  });

  group('SummaryPromptStore 预置与选择', () {
    test('默认存储：3 个预置，选中标准会议纪要', () {
      const SummaryPromptStore store = SummaryPromptStore();
      expect(store.allPrompts().length, 3);
      expect(store.selectedId, SummaryPrompt.builtinCurrentId);
      expect(
        store.allPrompts().map((SummaryPrompt p) => p.name).toList(),
        <String>['标准会议纪要', '面试复盘', '日常聊天回顾'],
      );
      // 预置模板内容非空且含必需占位符。
      for (final SummaryPrompt p in store.allPrompts()) {
        if (p.id == SummaryPrompt.builtinCurrentId) {
          expect(p.content, isEmpty); // 内容运行时从资产解析
        } else {
          expect(p.content, contains('{{meeting_content}}'));
          expect(p.content.trim(), isNotEmpty);
        }
      }
    });

    test('面试复盘预置：覆盖提问清单 / 未答上问题 / 复盘结构', () {
      final SummaryPrompt interview = builtinPrompts().firstWhere(
        (SummaryPrompt p) => p.id == SummaryPrompt.builtinInterviewId,
      );
      expect(interview.content, contains('提问清单'));
      expect(interview.content, contains('未答上'));
      expect(interview.content, contains('改进行动计划'));
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

    test('选中项被删除 → 回落标准会议纪要（effectiveSelection）', () {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-9',
        name: 'x',
        content: 'c {{meeting_content}}',
        builtin: false,
      );
      final SummaryPromptStore withCustom = const SummaryPromptStore(
        customs: <SummaryPrompt>[custom],
      ).copyWith(selectedId: 'custom-9');
      expect(withCustom.effectiveSelection().id, 'custom-9');

      // 删除后：store 仍持有失效 selectedId → 回落预置首个。
      final SummaryPromptStore afterDelete = withCustom.copyWith(
        customs: <SummaryPrompt>[],
      );
      expect(afterDelete.effectiveSelection().id, SummaryPrompt.builtinCurrentId);
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
  });

  group('生成接线（loadSelectedPrompt / buildMinutesMessages）', () {
    test('builtin-current → templateOverride 为 null（走资产默认路径）', () async {
      setMinutesTemplateForTesting('# 标准纪要\n{{meeting_content}}');
      final (String name, String? override) = await loadSelectedPrompt();
      expect(name, '标准会议纪要');
      expect(override, isNull);
      clearMinutesTemplateCache();
    });

    test('选中自定义 → override 为模板内容，插值注入逐字稿', () async {
      const SummaryPrompt custom = SummaryPrompt(
        id: 'custom-2',
        name: '要点提炼',
        content: '要点提炼任务：\n{{meeting_content}}',
        builtin: false,
      );
      await saveSummaryPromptStore(
        const SummaryPromptStore(selectedId: 'custom-2', customs: <SummaryPrompt>[custom]),
      );
      final (String name, String? override) = await loadSelectedPrompt();
      expect(name, '要点提炼');
      expect(override, contains('要点提炼任务'));

      final List<LlmMessage> messages = await buildMinutesMessages(
        _meeting(),
        templateOverride: override,
      );
      expect(messages.length, 2);
      // 自定义模板 → 通用 system 消息（非知识管家）。
      expect(messages[0].content, contains('记录整理助手'));
      // 逐字稿注入点已插值（含原文与说话人）。
      expect(messages[1].content, contains('数据库索引的原理'));
      expect(messages[1].content, contains('要点提炼任务'));
      expect(messages[1].content, isNot(contains('{{meeting_content}}')));
    });
  });
}
