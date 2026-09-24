import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/core/sse/sse_parser.dart';

/// 把若干字符串作为「分块到达」的字节流。
Stream<List<int>> _chunks(List<String> parts) {
  return Stream<List<int>>.fromIterable(
    parts.map((String s) => Uint8List.fromList(utf8.encode(s))),
  );
}

void main() {
  group('parseSse', () {
    test('只处理 data: 行，忽略 event: 与注释行', () async {
      final List<Map<String, dynamic>> events = await parseSse(_chunks(<String>[
        'event: foo\n',
        ': heartbeat\n',
        'data: {"a": 1}\n\n',
        'data: {"a": 2}\n\n',
      ])).toList();

      expect(events.length, 2);
      expect(events[0]['a'], 1);
      expect(events[1]['a'], 2);
    });

    test('跨 chunk 分片能正确拼接（半个 JSON 被切开）', () async {
      final List<Map<String, dynamic>> events = await parseSse(_chunks(<String>[
        'data: {"x":',
        '42}\n\n',
      ])).toList();

      expect(events.length, 1);
      expect(events[0]['x'], 42);
    });

    test('data: [DONE] 立即结束流，且哨兵不 emit', () async {
      final List<Map<String, dynamic>> events = await parseSse(_chunks(<String>[
        'data: {"a": 1}\n\n',
        'data: [DONE]\n\n',
        'data: {"a": 2}\n\n',
      ])).toList();

      expect(events.length, 1);
      expect(events[0]['a'], 1);
    });

    test('非法 JSON 行被忽略，不抛错（与原 Node 版一致）', () async {
      final List<Map<String, dynamic>> events = await parseSse(_chunks(<String>[
        'data: not-json\n\n',
        'data: {"ok": true}\n\n',
      ])).toList();

      expect(events.length, 1);
      expect(events[0]['ok'], isTrue);
    });

    test('流结束时残留的最后一行仍会被解析', () async {
      final List<Map<String, dynamic>> events = await parseSse(_chunks(<String>[
        'data: {"tail": 1}',
      ])).toList();

      expect(events.length, 1);
      expect(events[0]['tail'], 1);
    });
  });

  group('sseDeltaContent', () {
    test('取出 choices[0].delta.content', () {
      expect(
        sseDeltaContent(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'delta': <String, dynamic>{'content': '你好'},
            },
          ],
        }),
        '你好',
      );
    });

    test('丢弃 reasoning_content（只要正文）', () {
      expect(
        sseDeltaContent(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'delta': <String, dynamic>{'reasoning_content': '思考中'},
            },
          ],
        }),
        isNull,
      );
    });

    test('空 content 与缺失 choices 均返回 null', () {
      expect(
        sseDeltaContent(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'delta': <String, dynamic>{'content': ''},
            },
          ],
        }),
        isNull,
      );
      expect(sseDeltaContent(<String, dynamic>{}), isNull);
      expect(sseDeltaContent(<String, dynamic>{'choices': <dynamic>[]}), isNull);
    });
  });
}
