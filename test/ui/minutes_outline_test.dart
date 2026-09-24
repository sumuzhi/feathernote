import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/utils/minutes_outline.dart';

const String _sample = '''
# 分享主题
Q3 产品规划复盘

# 核心观点
本次会议围绕 Q3 产品规划展开，共 8 位发言人参与。核心共识是将新用户激活率目标定为 35%，
并要求渠道合作在 8 月底前完成落地，运营侧的排期需同步调整。

# 内容总结
## 一、重要决策
1. Q3 激活率目标从 30% 上调至 35%，采用新统计口径。
2. 渠道合作协议由商务团队在 8 月底前签署完成。
3. 运营排期提前两周，素材需在周三前交付。

## 二、讨论要点
- 激活率按新口径重算后实际完成 82%，此前未达标系统计口径问题。
- 用户访谈反馈引导页过长，是激活链路最主要的流失点。

# 金句摘录
> 口径不对，数据全错。
''';

void main() {
  group('parseMinutesOutline', () {
    final MinutesOutline outline = parseMinutesOutline(_sample);

    test('摘要取「核心观点」并统计字数', () {
      expect(outline.summary.contains('Q3 产品规划'), isTrue);
      expect(outline.summaryChars, greaterThan(40));
    });

    test('摘要所在分节不再出现在展示分节里', () {
      expect(
        outline.sections.any((MinutesSection s) => s.title.contains('核心观点')),
        isFalse,
      );
    });

    test('识别分节与条目', () {
      final List<MinutesSection> itemized = outline.itemizedSections;
      final MinutesSection decisions = itemized.firstWhere(
        (MinutesSection s) => s.title.contains('决策'),
      );
      expect(decisions.items.length, 3);
      expect(decisions.total, 3);
      expect(decisions.noun, '决策');
      expect(decisions.items.first, contains('35%'));

      final MinutesSection points = itemized.firstWhere(
        (MinutesSection s) => s.title.contains('要点'),
      );
      expect(points.items.length, 2);
      expect(points.noun, '要点');
    });

    test('标题序号前缀被规范化', () {
      final List<String> titles =
          outline.sections.map((MinutesSection s) => s.title).toList();
      expect(titles, contains('重要决策'));
      expect(titles, contains('讨论要点'));
      expect(titles.any((String t) => t.startsWith('一、')), isFalse);
    });

    test('模型自报条数优先（共 N 条）', () {
      const String raw = '# 重要决策\n共 8 条\n- 第一条\n- 第二条\n';
      final MinutesOutline parsed = parseMinutesOutline(raw);
      final MinutesSection section = parsed.itemizedSections.single;
      expect(section.items.length, 2);
      expect(section.total, 8);
      expect(section.noun, '决策');
    });

    test('空输入不崩且 isEmpty 为真', () {
      final MinutesOutline empty = parseMinutesOutline('');
      expect(empty.isEmpty, isTrue);
      expect(empty.summaryChars, 0);
      expect(empty.itemizedSections, isEmpty);
    });

    test('无标题的纯正文回退为摘要', () {
      final MinutesOutline parsed = parseMinutesOutline('这是一段没有结构的纪要正文。');
      expect(parsed.summary, '这是一段没有结构的纪要正文。');
      expect(parsed.sections, isEmpty);
    });
  });

  group('cleanInline / normalizeSectionTitle / parseListItem', () {
    test('清理行内标记', () {
      expect(cleanInline('**加粗**与`代码`'), '加粗与代码');
      expect(cleanInline('[链接](https://x.com)'), '链接');
      expect(cleanInline('~~删除~~'), '删除');
    });

    test('去序号', () {
      expect(normalizeSectionTitle('一、重要决策'), '重要决策');
      expect(normalizeSectionTitle('2. 讨论要点'), '讨论要点');
      expect(normalizeSectionTitle('模块三：注意事项'), '注意事项');
    });

    test('列表项解析', () {
      expect(parseListItem('- 一条要点'), '一条要点');
      expect(parseListItem('3、第三条'), '第三条');
      expect(parseListItem('普通正文'), isNull);
      expect(parseListItem('   '), isNull);
    });
  });
}
