/// 关键屏幕在窄屏 / 常规屏下的横向溢出冒烟测试。
///
/// 背景：真机反馈「点击录音后页面右侧出现 bug」——RenderFlex 溢出会在
/// debug 产物右缘渲染黄黑条纹。这里用 320dp（小屏）与 360dp（主流）
/// 两种宽度直接 pump 屏幕组件，任何横向溢出都会以异常形式暴露。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_minutes_flutter/ui/screens/profile_screen.dart';
import 'package:smart_minutes_flutter/ui/screens/recording_screen.dart';
import 'package:smart_minutes_flutter/ui/theme/app_theme.dart';
import 'package:smart_minutes_flutter/ui/widgets/speaker_chips.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';

/// 以逻辑像素直接设定测试视口（dpr=1，physicalSize 即逻辑尺寸）。
void _setViewport(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

RecordingScreen _recording({List<TranscriptItemView>? items}) {
  return RecordingScreen(
    title: '录音中',
    subtitle: '会议模式 · 已识别 8 人',
    clock: '123:45',
    speakers: List<SpeakerChipView>.generate(
      8,
      (int i) => SpeakerChipView(ordinal: i + 1, label: '说话人 ${i + 1}'),
    ),
    items: items ?? const <TranscriptItemView>[],
    liveTag: '自动滚动',
    paused: false,
    onClose: () {},
    onSettings: () {},
    onPauseToggle: () {},
    onStop: () {},
    onBookmark: () {},
    onTabTap: (int _) {},
    showBackToBottom: true,
    onBackToBottom: () {},
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
            value: 'qwen3.7-plus（很长很长的模型名占位文本）',
          ),
          ProfileSettingView(
            icon: Icons.groups_rounded,
            title: '说话人分离',
            subtitle: '声纹聚类 · 自动标注',
            toggle: true,
            toggleValue: true,
            switchLabel: '说话人分离',
            onToggle: (bool _) {},
          ),
        ],
      ),
      const ProfileSectionView(
        title: '实时链路自检',
        rows: <ProfileSettingView>[
          ProfileSettingView(
            icon: Icons.cable_rounded,
            title: '引擎 / 降级',
            subtitle: '已降级：一段相当长的降级原因占位文本，用于压测行宽',
            value: 'RealtimeDashScopeEngine',
          ),
        ],
      ),
    ],
    onSettings: () {},
    onTabTap: (int _) {},
  );
}

void main() {
  final List<Size> sizes = <Size>[const Size(320, 690), const Size(360, 800)];

  for (final Size size in sizes) {
    group('RecordingScreen @ ${size.width}dp', () {
      testWidgets('空列表不横向溢出', (WidgetTester tester) async {
        _setViewport(tester, size);
        await tester.pumpWidget(_host(_recording()));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('长转写文本不横向溢出', (WidgetTester tester) async {
        _setViewport(tester, size);
        await tester.pumpWidget(
          _host(
            _recording(
              items: <TranscriptItemView>[
                TranscriptItemView(
                  ordinal: 1,
                  speakerLabel: '说话人 1',
                  timeLabel: '00:12',
                  text: '这是一段非常长的转写文本' * 12,
                  segmentId: 'seg_1',
                  startTimeMs: 0,
                  endTimeMs: 8000,
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('ProfileScreen @ ${size.width}dp 不横向溢出', (WidgetTester tester) async {
      _setViewport(tester, size);
      await tester.pumpWidget(_host(_profile()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
