/// 屏 14 / 屏 15 的设计稿还原回归测试。
///
/// 断言两屏在 390×844（设计稿画布）下无溢出、关键文案逐字一致、关键几何
/// 与 HTML 的 `page-offset` 对齐（HTML 的 y 减去 62 的状态栏高即为期望值，
/// 例：OverallCard 214→152、StepsCard 331→269、底部按钮行 772→772）。
///
/// 注意：`flutter test` 的默认测试字体比设计字体宽，被 FittedBox 轻缩的
/// 单行文案会带来 1~2px 的高度差，几何断言留 2px 容差。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/import_idle_screen.dart';
import 'package:smart_minutes_flutter/ui/screens/import_processing_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/app_tab_bar.dart';
import 'package:smart_minutes_flutter/ui/widgets/history_card.dart';

/// 按设计稿画布（390×844）挂载被测屏幕。
Future<void> _pumpAt390(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: screen));
  // 步骤 ② 的转圈是无限动画，只 pump 固定时长，不用 pumpAndSettle。
  await tester.pump(const Duration(milliseconds: 50));
}

void _noop() {}

/// 屏 15「处理中」的四步（与 HTML 屏 15 同状态：①完成 ②进行 48% ③④等待）。
const List<ImportStepView> _runningSteps = <ImportStepView>[
  ImportStepView(
    index: 1,
    title: '上传文件',
    subtitle: '248 MB · 已上传完成',
    status: 'done',
  ),
  ImportStepView(
    index: 2,
    title: '分离音轨',
    subtitle: '正在从视频中提取音频轨道 · AAC 48kHz',
    status: 'running',
    percent: 0.48,
  ),
  ImportStepView(
    index: 3,
    title: '语音转写',
    subtitle: '音轨分离完成后自动开始',
    status: 'idle',
  ),
  ImportStepView(
    index: 4,
    title: 'AI 生成纪要',
    subtitle: '转写完成后自动开始',
    status: 'idle',
  ),
];

void main() {
  testWidgets('屏14 有最近导入：无溢出 + 拖拽区/最近卡几何对齐设计稿', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      ImportIdleScreen(
        onPickFile: _noop,
        onTabTap: (int _) {},
        onBack: _noop,
        recentItems: const <HistoryItemView>[
          HistoryItemView(
            title: '产品评审_录屏.mp4',
            description: '',
            meta: '248 MB · 42 分钟 · 已生成纪要',
          ),
          HistoryItemView(
            title: '客户访谈_0312.m4a',
            description: '',
            meta: '86 MB · 35 分钟 · 已生成纪要',
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    // 屏 14 不再渲染底部 Tab 栏（产品指令）。
    expect(find.byType(AppTabBar), findsNothing);

    // 设计稿里的固定文案，一字不改。
    expect(find.text('导入音视频'), findsOneWidget);
    // 用户要求移除右上角「帮助」icon（原断言已随之删除）。
    expect(find.text('拖拽文件到此处'), findsOneWidget);
    expect(find.text('MP4 / MOV / MP3 / WAV · 单个文件 ≤ 2GB'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.text('音频文件'), findsOneWidget);
    expect(find.text('视频文件'), findsOneWidget);
    expect(find.text('自动分离音轨'), findsOneWidget);
    expect(
      find.text('单个文件 ≤ 2GB · 时长 ≤ 4 小时；视频仅解析音轨，画面内容不参与分析'),
      findsOneWidget,
    );
    expect(find.text('最近导入'), findsOneWidget);

    // 拖拽区内层：350 − 18×2 = 314 宽。高度原为 148（52+6+22+6+16+6+40）；
    // 2026-10-09 字号对齐全局字阶（说明文案 11→12）后实测 149。
    final Size zone = tester.getSize(
      find
          .ancestor(of: find.text('拖拽文件到此处'), matching: find.byType(Column))
          .first,
    );
    expect(zone.width, closeTo(314, 0.5));
    expect(zone.height, closeTo(149, 0.5));

    // 最近卡片：350×60（字号对齐全局字阶后 meta 11→12，实测高 64）。
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.text('产品评审_录屏.mp4'),
              matching: find.byType(GestureDetector),
            )
            .first,
      ),
      const Size(350, 64),
    );
  });

  testWidgets('屏14 无最近导入：不渲染「最近导入」且无溢出', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      ImportIdleScreen(
        onPickFile: _noop,
        onTabTap: (int _) {},
        onBack: _noop,
        recentItems: const <HistoryItemView>[],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('最近导入'), findsNothing);
    expect(find.byType(AppTabBar), findsNothing);
  });

  testWidgets('屏15 处理中：无溢出 + 卡片位置对齐 HTML page-offset', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: '产品评审_录屏.mp4',
        subtitle: '248 MB · 42 分钟 12 秒',
        isVideo: true,
        steps: _runningSteps,
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    // 屏 15 按 HTML 无底部 Tab 栏。
    expect(find.byType(AppTabBar), findsNothing);

    // 设计稿固定文案。
    expect(find.text('处理中'), findsOneWidget);
    // 顶栏标准化后「后台处理」右上为 icon（原为文字链接），
    // 底部橙色主按钮仍是可见文字。
    expect(find.text('后台处理'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.text('整体进度'), findsOneWidget);
    expect(find.text('取消处理'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('上传文件'), findsOneWidget);
    expect(find.text('分离音轨'), findsOneWidget);
    expect(find.text('语音转写'), findsOneWidget);
    expect(find.text('AI 生成纪要'), findsOneWidget);
    expect(find.text('248 MB · 已上传完成'), findsOneWidget);
    expect(find.text('正在从视频中提取音频轨道 · AAC 48kHz'), findsOneWidget);
    expect(find.text('音轨分离完成后自动开始'), findsOneWidget);
    expect(find.text('转写完成后自动开始'), findsOneWidget);
    // 修复 ③：整体进度卡不再渲染 ETA tips（反复出现/隐藏导致抖动）。
    expect(
      find.textContaining('预计还需'),
      findsNothing,
    );
    expect(
      find.text('视频仅解析音轨，画面内容不参与分析；原文件不会被修改'),
      findsOneWidget,
    );
    // 修复 ①：整体进度按四步等权 —— ①完成(1.0) + ②48% + ③④0 =
    // (1.0+0.48)/4 ≈ 37%；步骤 ② 自身尾标仍为 48%。
    expect(find.text('37%'), findsOneWidget);
    expect(find.text('48%'), findsOneWidget);

    // 几何：顶栏标准化（AppTopBar，自带 page/6 padding）后内容整体 +6，
    // OverallCard 顶 152→158，标题行落在 174（原 HTML 基线 168）。
    expect(tester.getTopLeft(find.text('整体进度')).dy, closeTo(174, 0.5));
    // 文件卡标题：原 80 → 86。
    expect(tester.getTopLeft(find.text('产品评审_录屏.mp4')).dy, closeTo(86, 0.5));
    // 修复 ③：整体进度卡不再渲染 ETA tips 行，OverallCard 比旧实现矮约 30px，
    // 故 StepsCard 整体上移（旧实现 287）；字号映射 + 顶栏标准化后实测 266。
    expect(tester.getTopLeft(find.text('上传文件')).dy, closeTo(266, 2));
    // 说明条内文字区宽 350 − 14×2 = 322。
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('视频仅解析音轨，画面内容不参与分析；原文件不会被修改'),
                  matching: find.byType(Row),
                )
                .first,
          )
          .width,
      closeTo(322, 0.5),
    );
    // 底部按钮：各 169×48，文字行落在 772+ (48−22)/2 = 785。
    expect(
      tester.getSize(
        find.ancestor(of: find.text('取消处理'), matching: find.byType(Expanded)).first,
      ),
      const Size(169, 48),
    );
    expect(tester.getTopLeft(find.text('取消处理')).dy, closeTo(785, 1));
  });

  testWidgets('屏14 长列表滚到底：顶栏与返回箭头常驻', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      ImportIdleScreen(
        onPickFile: _noop,
        onTabTap: (int _) {},
        onBack: _noop,
        recentItems: List<HistoryItemView>.generate(
          12,
          (int i) => HistoryItemView(
            title: '会议_$i.mp4',
            description: '',
            meta: '10 MB · 1 分钟 · 已生成纪要',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // 本质断言：顶栏不在滚动容器子树内（header 在 SingleChildScrollView 之外）。
    expect(
      find.ancestor(of: find.text('导入音视频'), matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.chevron_left_rounded),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );

    final double titleBefore = tester.getTopLeft(find.text('导入音视频')).dy;
    final double backBefore = tester.getTopLeft(find.byIcon(Icons.chevron_left_rounded)).dy;

    // 滚到底部（12 条最近记录足以让内容超出一屏）。
    final ScrollPosition position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 滚动后顶栏与返回箭头仍在原位（不随内容滚走）且可见。
    expect(find.text('导入音视频'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(tester.getTopLeft(find.text('导入音视频')).dy, titleBefore);
    expect(tester.getTopLeft(find.byIcon(Icons.chevron_left_rounded)).dy, backBefore);
  });

  testWidgets('屏15 矮屏（390×500）滚动后：顶栏常驻', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: '产品评审_录屏.mp4',
        subtitle: '248 MB · 42 分钟 12 秒',
        isVideo: true,
        steps: _runningSteps,
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
      size: const Size(390, 500),
    );
    expect(tester.takeException(), isNull);

    // 顶栏不在滚动容器内。
    expect(
      find.ancestor(of: find.text('处理中'), matching: find.byType(Scrollable)),
      findsNothing,
    );

    final double titleBefore = tester.getTopLeft(find.text('处理中')).dy;
    final ScrollPosition position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.text('处理中'), findsOneWidget);
    expect(tester.getTopLeft(find.text('处理中')).dy, titleBefore);
    // 右上「后台处理」同样常驻可点。
    // 「后台处理」出现两次（顶栏链接 + 底部主按钮），两处都不在滚动容器内。
    expect(
      find.ancestor(of: find.text('后台处理'), matching: find.byType(Scrollable)),
      findsNothing,
    );
  });

  testWidgets('屏15 完成态：显示「查看纪要」与 100%', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: '产品评审_录屏.mp4',
        subtitle: '248 MB · 42 分钟 12 秒',
        isVideo: true,
        steps: <ImportStepView>[
          ImportStepView(index: 1, title: '上传文件', subtitle: '已上传完成', status: 'done'),
          ImportStepView(
            index: 2,
            title: '分离音轨',
            subtitle: '提取音频轨为 m4a，不解码零转码',
            status: 'done',
          ),
          ImportStepView(
            index: 3,
            title: '语音转写',
            subtitle: '区分说话人 · 生成逐字稿',
            status: 'done',
          ),
          ImportStepView(
            index: 4,
            title: 'AI 生成纪要',
            subtitle: '基于逐字稿生成结构化纪要',
            status: 'done',
          ),
        ],
        failureReason: null,
        allDone: true,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('查看纪要'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('屏15 失败态（音频，② 无需分离）：红叉 + 失败原因 + 「关闭」', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: '客户访谈_0312.m4a',
        subtitle: '86 MB · 35 分钟 2 秒',
        isVideo: false,
        steps: <ImportStepView>[
          ImportStepView(index: 1, title: '上传文件', subtitle: '已上传完成', status: 'done'),
          ImportStepView(
            index: 2,
            title: '解析音频',
            subtitle: '读取音频元信息',
            status: 'skip',
            skip: true,
          ),
          ImportStepView(
            index: 3,
            title: '语音转写',
            subtitle: '区分说话人 · 生成逐字稿',
            status: 'failed',
          ),
          ImportStepView(
            index: 4,
            title: 'AI 生成纪要',
            subtitle: '转写完成后自动开始',
            status: 'idle',
          ),
        ],
        failureReason: '网络中断，请检查网络后重试',
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('导入失败'), findsOneWidget);
    expect(find.text('网络中断，请检查网络后重试'), findsOneWidget);
    expect(find.text('无需分离'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.text('音频将直接解析音轨；原文件不会被修改'), findsOneWidget);
  });

  testWidgets('屏15 窄屏 320×640 仍可滚动且无溢出', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: '产品评审_录屏.mp4',
        subtitle: '248 MB · 42 分钟 12 秒',
        isVideo: true,
        steps: _runningSteps,
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });

  // ── 修复 ①：整体进度四步等权回归 ──

  testWidgets('屏15 整体进度：①完成 + ②③④等待（视频，②idle）= 25%', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: 't',
        subtitle: 's',
        isVideo: true,
        steps: <ImportStepView>[
          ImportStepView(index: 1, title: '上传文件', subtitle: '', status: 'done'),
          ImportStepView(index: 2, title: '分离音轨', subtitle: '', status: 'idle'),
          ImportStepView(index: 3, title: '语音转写', subtitle: '', status: 'idle'),
          ImportStepView(index: 4, title: 'AI 生成纪要', subtitle: '', status: 'idle'),
        ],
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    // 仅 ①完成 → 1/4 = 25%（旧实现会把单步当 100%，错误显示 100%）。
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('屏15 整体进度：①②完成 + ③④等待 = 50%', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: 't',
        subtitle: 's',
        isVideo: true,
        steps: <ImportStepView>[
          ImportStepView(index: 1, title: '上传文件', subtitle: '', status: 'done'),
          ImportStepView(index: 2, title: '分离音轨', subtitle: '', status: 'done'),
          ImportStepView(index: 3, title: '语音转写', subtitle: '', status: 'idle'),
          ImportStepView(index: 4, title: 'AI 生成纪要', subtitle: '', status: 'idle'),
        ],
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    // ①②完成 → 2/4 = 50%。
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('屏15 整体进度：①完成 + ②进行 60% + ③④等待 = 40%', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: 't',
        subtitle: 's',
        isVideo: true,
        steps: <ImportStepView>[
          ImportStepView(index: 1, title: '上传文件', subtitle: '', status: 'done'),
          ImportStepView(index: 2, title: '分离音轨', subtitle: '', status: 'running', percent: 0.6),
          ImportStepView(index: 3, title: '语音转写', subtitle: '', status: 'idle'),
          ImportStepView(index: 4, title: 'AI 生成纪要', subtitle: '', status: 'idle'),
        ],
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    // (1.0 + 0.6) / 4 = 0.4 → 40%；步骤 ② 自身尾标仍显示 60%。
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('屏15 处理中（非失败）：不渲染失败原因行', (WidgetTester tester) async {
    await _pumpAt390(
      tester,
      const ImportProcessingScreen(
        title: 't',
        subtitle: 's',
        isVideo: true,
        steps: _runningSteps,
        failureReason: null,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('网络'), findsNothing);
  });
}
