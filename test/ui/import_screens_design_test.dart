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
    expect(find.text('帮助'), findsOneWidget);
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

    // 拖拽区内层：350 − 18×2 = 314 宽、148 高（52+6+22+6+16+6+40）。
    final Size zone = tester.getSize(
      find
          .ancestor(of: find.text('拖拽文件到此处'), matching: find.byType(Column))
          .first,
    );
    expect(zone.width, closeTo(314, 0.5));
    expect(zone.height, closeTo(148, 0.5));

    // 最近卡片：350×60。
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.text('产品评审_录屏.mp4'),
              matching: find.byType(GestureDetector),
            )
            .first,
      ),
      const Size(350, 60),
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
        detail: null,
        etaMinutes: 2,
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
    // 「后台处理」在设计稿里出现两次：顶栏右侧链接 + 底部橙色主按钮。
    expect(find.text('后台处理'), findsNWidgets(2));
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
    expect(
      find.text('预计还需约 2 分钟 · 可点右上角「后台处理」继续其他操作'),
      findsOneWidget,
    );
    expect(
      find.text('视频仅解析音轨，画面内容不参与分析；原文件不会被修改'),
      findsOneWidget,
    );
    // 整体进度与步骤 ② 都是 48%（设计稿同值）。
    expect(find.text('48%'), findsNWidgets(2));

    // 几何：OverallCard 顶 152（HTML 214 − 62），标题行 152+16 = 168。
    expect(tester.getTopLeft(find.text('整体进度')).dy, closeTo(168, 0.5));
    // 文件卡 64..136（HTML 126 − 62），卡内 44 图标行居中 → 标题落在 80。
    expect(tester.getTopLeft(find.text('产品评审_录屏.mp4')).dy, closeTo(80, 0.5));
    // StepsCard 顶 269（HTML 331 − 62）+ 内边距 18 → 步骤 ① 落在 287。
    expect(tester.getTopLeft(find.text('上传文件')).dy, closeTo(287, 2));
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
        detail: null,
        etaMinutes: 0,
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
        detail: '网络中断，请检查网络后重试',
        etaMinutes: 0,
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
        detail: null,
        etaMinutes: 2,
        allDone: false,
        onBack: _noop,
        onCancel: _noop,
        onViewMinutes: _noop,
      ),
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
  });
}
