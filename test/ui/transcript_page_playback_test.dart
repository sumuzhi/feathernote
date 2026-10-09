/// **页面级**播放回归：从真实 TranscriptPage 出发，点击播放按钮，断言
/// 播放组件出现在**被点击的那一条**上，以及暂停后进度条停在断点。
///
/// 只测控制器不够——此前「定位对了但组件不显示/被重置」的问题发生在
/// 「控制器 → 页面 → 列表 → 条目」这条链路上，必须在页面层才复现得出来。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smart_minutes_flutter/backend/backend_api.dart';
import 'package:smart_minutes_flutter/backend/services/import_service.dart';
import 'package:smart_minutes_flutter/domain/enums.dart';
import 'package:smart_minutes_flutter/domain/meeting.dart';
import 'package:smart_minutes_flutter/domain/segment.dart';
import 'package:smart_minutes_flutter/domain/speaker.dart';
import 'package:smart_minutes_flutter/ui/pages/transcript_page.dart';
import 'package:smart_minutes_flutter/ui/providers/app_providers.dart';
import 'package:smart_minutes_flutter/ui/providers/audio_player_controller.dart';
import 'package:smart_minutes_flutter/ui/widgets/transcript_tile.dart';



/// 可控假播放器引擎（本文件自持，避免跨文件引用私有类）。
class _FakeEngine implements AudioPlayerEngine {
  String? lastPath;
  int? lastSeekMs;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int setFilePathCalls = 0;
  final StreamController<Duration> _positionCtrl = StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _stateCtrl = StreamController<PlayerState>.broadcast();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  Future<Duration?> setFilePath(String path) async {
    setFilePathCalls++;
    lastPath = path;
    return _duration;
  }

  @override
  Future<void> play() async {
    playCalls++;
    _stateCtrl.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _stateCtrl.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    lastSeekMs = position.inMilliseconds;
    _position = position;
    _positionCtrl.add(_position);
  }

  @override
  Duration get currentPosition => _position;
  @override
  Duration? get duration => _duration;


  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;

  @override
  Future<void> dispose() async {
    await _positionCtrl.close();
    await _stateCtrl.close();
  }

  void tickTo(int ms) {
    _position = Duration(milliseconds: ms);
    _positionCtrl.add(_position);
  }

  set duration(Duration value) => _duration = value;
}

/// 三条固定段落（起点 0 / 3000 / 6000，段长 10s）。
const List<List<int>> kSegments = <List<int>>[
  <int>[0, 10000],
  <int>[3000, 13000],
  <int>[6000, 16000],
];

class _FakeApi implements BackendApi {

  // ── 导入音视频（BackendApi 增量 stub：导入流程不在本 UI 测试范围）──

  @override
  Future<Meeting> startImport(ImportRequest req) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelImport(String meetingId) async {}

  @override
  Future<void> retryImport(String meetingId) async {}

  @override
  Stream<ImportProgressEvent> get importEvents =>
      const Stream<ImportProgressEvent>.empty();
  @override
  Future<Meeting?> getMeeting(String id) async => Meeting(
        id: id,
        title: '测试会议',
        createdAt: DateTime(2026, 9, 25, 10),
        durationMs: 30000,
        sampleRate: 16000,
        speakerCount: 1,
        status: MeetingStatus.stopped,
        source: MeetingSource.microphone,
        finalizeStatus: FinalizeStatus.none,
        transcriptSource: TranscriptSource.realtime,
        audioStatus: AudioStatus.done,
        audioBytes: 1000,
        minutesPartial: false,
        audioKey: id,
        segments: <TranscriptSegment>[
          for (int i = 0; i < kSegments.length; i++)
            TranscriptSegment(
              meetingId: id,
              segmentId: 'seg_$i',
              ordinal: i,
              speakerId: 'sp1',
              speakerName: '说话人 1',
              text: '第 $i 段正文',
              startTime: kSegments[i][0],
              endTime: kSegments[i][1],
              confidence: 0.9,
              seqStart: 0,
              seqEnd: 1,
            ),
        ],
        speakers: const <Speaker>[],
      );

  @override
  Stream<List<TranscriptSegment>> watchSegments(String meetingId) async* {
    final Meeting? meeting = await getMeeting(meetingId);
    yield meeting?.segments ?? <TranscriptSegment>[];
  }

  @override
  Future<String?> getAudioPath(String meetingId) async => '/tmp/m.wav';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _boot(_FakeEngine engine) => ProviderContainer(
      overrides: [
        backendProvider.overrideWith((Ref ref) async => _FakeApi()),
        audioPlayerControllerProvider.overrideWith(
          () => AudioPlayerController(engine: engine),
        ),
      ],
    );

/// 播放组件（进度条右侧的「已播 / 段长」文本）。
/// 播放组件（进度条右侧的「已播 / 段长」，形如 `0:03 / 0:10`）。
Finder get _component =>
    find.textContaining(RegExp(r'\d+:\d\d / \d+:\d\d'));

TranscriptTile _owner(WidgetTester tester) => tester.widget<TranscriptTile>(
      find.ancestor(of: _component, matching: find.byType(TranscriptTile)),
    );


/// 点击第 [index] 条上的播放入口（用条目内的第一个 GestureDetector = 时间标签）。
///
/// 不能直接 `find.byIcon(Icons.play_arrow_rounded).at(i)`：播放中该条按钮会换成
/// 自定义的暂停图标（不是 Icon），图标数量会变，`.at(i)` 会点到别的段上去。
///
/// ⚠️ 列表已改 `ListView.builder` 虚拟化（性能修复）：视口外的条目**不会被构建**，
/// 必须按段文本定位目标条目并先滚动到可见，再按「条目内第一个 GestureDetector」点击。
/// 不能用 `.at(index)`——虚拟化下 widget 树里只有窗口内的条目，下标会越界。
Future<void> _tapTile(WidgetTester tester, int index) async {
  final Finder tile = find.ancestor(
    of: find.text('第 $index 段正文'),
    matching: find.byType(TranscriptTile),
  );
  // 滚动到可见（虚拟化下可能尚未构建）；已可见时 scrollUntilVisible 直接跳过。
  await tester.scrollUntilVisible(
    tile,
    160,
    scrollable: find
        .byWidgetPredicate((Widget w) => w is Scrollable && w.axis == Axis.vertical)
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: tile, matching: find.byType(GestureDetector)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首次点击播放：组件出现在被点击的那一条上', (WidgetTester tester) async {
    final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
    final ProviderContainer container = _boot(engine);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TranscriptPage(meetingId: 'm1')),
      ),
    );
    await tester.pumpAndSettle();

    // 虚拟化列表：视口内至少有 1 条被构建即视为渲染正常（不逐条点验数量）。
    expect(find.byType(TranscriptTile), findsWidgets);
    expect(_component, findsNothing, reason: '初始不应有播放组件');

    // 点第 2 条的播放入口。
    await _tapTile(tester, 1);

    expect(
      container.read(audioPlayerControllerProvider).isSegmentPlaying('seg_1', 3000),
      isTrue,
      reason: '控制器应认定第 2 条在播',
    );
    expect(_component, findsOneWidget, reason: '首次点击后组件必须出现');
    expect(_owner(tester).item.text, '第 1 段正文');
  });

  testWidgets('播放中推进 → 进度条前进；暂停 → 进度条停在断点不清零',
      (WidgetTester tester) async {
    final _FakeEngine engine = _FakeEngine()..duration = const Duration(seconds: 30);
    final ProviderContainer container = _boot(engine);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TranscriptPage(meetingId: 'm1')),
      ),
    );
    await tester.pumpAndSettle();

    await _tapTile(tester, 1);

    // 播到 6s（段内 3s）。
    engine.tickTo(6000);
    await tester.pumpAndSettle();
    expect(container.read(audioPlayerControllerProvider).currentPositionMs, 6000);
    expect(_owner(tester).item.playProgress, closeTo(0.3, 0.01));

    // 暂停：进度必须停在段内 3s，不得清零。
    await _tapTile(tester, 1);
    expect(
      container.read(audioPlayerControllerProvider).isSegmentPlaying('seg_1', 3000),
      isFalse,
      reason: '应已暂停',
    );
    expect(
      container.read(audioPlayerControllerProvider).isSegmentActive('seg_1', 3000),
      isTrue,
      reason: '暂停后仍是当前段，组件不得消失',
    );
    expect(_component, findsOneWidget, reason: '暂停后进度条应保留');
    expect(_owner(tester).item.playProgress, closeTo(0.3, 0.01), reason: '暂停不得把进度清零');

    // 继续播放：从断点继续（不回到段首 3000）。
    await _tapTile(tester, 1);
    expect(engine.lastSeekMs, 6000, reason: '续播必须回到断点 6000，而不是段首 3000');
    expect(
      container.read(audioPlayerControllerProvider).isSegmentPlaying('seg_1', 3000),
      isTrue,
    );
  });
}
