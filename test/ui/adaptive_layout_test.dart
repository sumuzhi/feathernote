/// 自适应布局矩阵测试：任意屏宽下容器必须占满全宽且无溢出。
///
/// 方法说明：不针对特定机型像素做断言，而是把关键屏放在一组**离散化取值
/// 覆盖连续区间**的视口（280–520dp，含超窄 / 主流 / 小平板）下逐一渲染：
/// 1. 根容器 render width == 视口宽度（占满全宽，不允许出现黑边 / 未铺满）；
/// 2. 渲染零异常（RenderFlex 溢出会以异常形式暴露）。
/// 任何把布局写死到某档像素、破坏自适应的改动都会在这里失败。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/profile_screen.dart';
import 'package:smart_minutes_flutter/ui/screens/recording_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/meeting_info_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/minutes_card.dart';
import 'package:smart_minutes_flutter/ui/widgets/speaker_chips.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';

/// 视口矩阵：覆盖 280dp 超窄机 → 520dp 小平板。
const List<Size> kViewports = <Size>[
  Size(280, 620),
  Size(320, 690),
  Size(360, 800),
  Size(393, 873),
  Size(412, 915),
  Size(520, 1000),
];

void _setViewport(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

RecordingScreen _recording() {
  return RecordingScreen(
    title: '录音中',
    subtitle: '会议模式 · 已识别 8 人',
    clock: '1:23:45',
    speakers: List<SpeakerChipView>.generate(
      8,
      (int i) => SpeakerChipView(ordinal: i + 1, label: '说话人 ${i + 1}'),
    ),
    items: const <TranscriptItemView>[],
    liveTag: '自动滚动',
    paused: false,
    onClose: () {},
    onSettings: () {},
    onPauseToggle: () {},
    onStop: () {},
    onBookmark: () {},
    onTabTap: (int _) {},
  );
}

ProfileScreen _profile() {
  return ProfileScreen(
    stats: const <ProfileStatView>[
      ProfileStatView(value: '128', label: '场会议'),
      ProfileStatView(value: '64h', label: '累计时长'),
      ProfileStatView(value: '96', label: '场已总结'),
    ],
    sections: <ProfileSectionView>[
      ProfileSectionView(
        title: '模型与转写',
        rows: <ProfileSettingView>[
          const ProfileSettingView(
            icon: Icons.auto_awesome_rounded,
            title: '纪要模型',
            subtitle: '摘要策略 · knowledge-extract',
            value: 'qwen3.7-plus（超长模型名压测占位）',
          ),
          ProfileSettingView(
            icon: Icons.groups_rounded,
            title: '说话人分离',
            subtitle: '声纹聚类 · 自动标注',
            toggle: true,
            toggleValue: true,
            onToggle: (bool _) {},
          ),
        ],
      ),
    ],
    versionText: '版本 1.0.0 · 端化运行 · 0925-2300/740ca3d',
    onSettings: () {},
    onTabTap: (int _) {},
  );
}

/// 断言「被测组件的渲染宽度 == 视口宽度」（占满全宽）。
///
/// StatelessWidget 根的 renderObject 含自身 margin（Container margin 在
/// 渲染树里表现为 Padding 包裹），所以无论是否带页边距，根宽都应等于视口宽。
void _expectAdaptiveWidth(WidgetTester tester, Type type, Size viewport) {
  final RenderObject? renderObject =
      tester.element(find.byType(type)).renderObject;
  expect(renderObject, isNotNull, reason: '$type 未挂载');
  final double actual = renderObject!.semanticBounds.size.width;
  expect(
    (actual - viewport.width).abs(),
    lessThan(0.5),
    reason: '$type 在 ${viewport.width}dp 视口下宽度 $actual，'
        '期望 ${viewport.width} —— 自适应被破坏（黑边 / 未铺满 / 写死像素）',
  );
}

void main() {
  for (final Size viewport in kViewports) {
    group('自适应 @ ${viewport.width}x${viewport.height}dp', () {
      testWidgets('RecordingScreen 占满全宽且无溢出', (WidgetTester tester) async {
        _setViewport(tester, viewport);
        await tester.pumpWidget(_host(_recording()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectAdaptiveWidth(tester, RecordingScreen, viewport);
      });

      testWidgets('ProfileScreen 占满全宽且无溢出', (WidgetTester tester) async {
        _setViewport(tester, viewport);
        await tester.pumpWidget(_host(_profile()));
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectAdaptiveWidth(tester, ProfileScreen, viewport);
      });

      testWidgets('MeetingInfoCard 占满全宽且无溢出', (WidgetTester tester) async {
        _setViewport(tester, viewport);
        await tester.pumpWidget(
          _host(
            MeetingInfoCard(
              title: '会议 09-25 22:49',
              meta: '低于 1 分钟 · 1 位说话人 · 今天 14:49',
              transcriptChars: '1,860 字 ›',
              onOpenTranscript: () {},
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectAdaptiveWidth(tester, MeetingInfoCard, viewport);
      });

      testWidgets('MinutesCard 占满全宽且无溢出', (WidgetTester tester) async {
        _setViewport(tester, viewport);
        await tester.pumpWidget(
          _host(
            SingleChildScrollView(
              child: MinutesCard(
                view: MinutesView(
                  title: '✦ AI 结构化纪要',
                  modelTag: 'qwen3.7-plus',
                  abstractText: '本次提供的录音文件时长极短（7秒），' * 3,
                  sections: const <MinutesSectionView>[
                    MinutesSectionView(
                      title: '重要决策',
                      items: <String>['激活率目标上调至 35%。'],
                    ),
                  ],
                  transcriptChars: '13 字 ›',
                  onOpenTranscript: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectAdaptiveWidth(tester, MinutesCard, viewport);
      });
    });
  }
}
