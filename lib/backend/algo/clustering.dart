/// 声纹余弦相似度与说话人聚类（**逐行移植** `server/src/core/clustering.js`）。
///
/// - [cosineSimilarity]：单次余弦；
/// - [OnlineClusterer]：实时在线聚类（增量质心），阈值默认 0.75；
/// - [globalRecluster]：会后全局重聚类（平均连接凝聚），按各簇最早片段
///   `start_time` 升序重排 `spk_1..spk_n`，保证编号稳定可解释。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../../domain/segment.dart';
import '../../../domain/speaker.dart';

/// 默认聚类阈值。
const double kDefaultThreshold = 0.75;

/// 向量 L2 归一化（0 向量返回原值，避免除零）。
Float64List normalize(List<double> v) {
  double norm = 0;
  for (int i = 0; i < v.length; i++) {
    norm += v[i] * v[i];
  }
  norm = math.sqrt(norm);
  if (norm == 0) norm = 1;
  final Float64List out = Float64List(v.length);
  for (int i = 0; i < v.length; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}

/// 余弦相似度（含 1e-9 平滑，与原实现一致）。
double cosineSimilarity(List<double> a, List<double> b) {
  final int len = a.length < b.length ? a.length : b.length;
  double dot = 0;
  double na = 0;
  double nb = 0;
  for (int i = 0; i < len; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (math.sqrt(na) * math.sqrt(nb) + 1e-9);
}

/// 在线说话人聚类器：对每个新片段向量给出 `spk_N` 归属。
class OnlineClusterer {
  /// 构造聚类器。
  OnlineClusterer({this.threshold = kDefaultThreshold});

  /// 余弦阈值。
  final double threshold;

  /// 各簇归一化质心。
  final List<List<double>> centroids = <List<double>>[];

  /// 各簇累计样本数。
  final List<int> counts = <int>[];

  /// 分配说话人 ID（`spk_1` / `spk_2` / …）。
  String assign(List<double> vector) {
    int bestIndex = -1;
    double bestScore = -1;
    for (int i = 0; i < centroids.length; i++) {
      final double score = cosineSimilarity(vector, centroids[i]);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex >= 0 && bestScore >= threshold) {
      _update(bestIndex, vector);
      return 'spk_${bestIndex + 1}';
    }
    centroids.add(normalize(List<double>.from(vector)));
    counts.add(1);
    return 'spk_${centroids.length}';
  }

  /// 已发现的说话人数量。
  int size() => centroids.length;

  /// 增量更新质心。
  void _update(int index, List<double> vector) {
    final int count = counts[index];
    final List<double> merged = List<double>.generate(
      centroids[index].length,
      (int j) => (centroids[index][j] * count + vector[j]) / (count + 1),
    );
    centroids[index] = normalize(merged);
    counts[index] = count + 1;
  }
}

/// 参与全局重聚类的片段视图。
class ReclusterInput {
  /// 构造输入。
  const ReclusterInput({required this.segmentId, required this.startTime, required this.vector});

  /// 片段 ID。
  final String segmentId;

  /// 起始时间（毫秒）。
  final int startTime;

  /// 声纹向量。
  final List<double> vector;
}

/// 会后全局重聚类（平均连接法 + 质心余弦合并）。
///
/// 返回 `segment_id -> speaker_id` 映射（按最早出现顺序编号）。
Map<String, String> globalRecluster(List<ReclusterInput> segments, {double threshold = kDefaultThreshold}) {
  final Map<String, String> map = <String, String>{};
  if (segments.isEmpty) return map;

  final List<_Cluster> clusters = <_Cluster>[
    for (int index = 0; index < segments.length; index++)
      _Cluster(members: <int>[index], sum: List<double>.from(segments[index].vector), count: 1),
  ];

  List<double> centroidOf(_Cluster cluster) => normalize(
    List<double>.generate(cluster.sum.length, (int i) => cluster.sum[i] / cluster.count),
  );

  for (;;) {
    int bestA = -1;
    int bestB = -1;
    double bestScore = threshold;
    for (int i = 0; i < clusters.length; i++) {
      for (int j = i + 1; j < clusters.length; j++) {
        final double score = cosineSimilarity(centroidOf(clusters[i]), centroidOf(clusters[j]));
        if (score > bestScore) {
          bestScore = score;
          bestA = i;
          bestB = j;
        }
      }
    }
    if (bestA < 0) break;
    final _Cluster target = clusters[bestA];
    final _Cluster source = clusters[bestB];
    target.members.addAll(source.members);
    for (int k = 0; k < target.sum.length; k++) {
      target.sum[k] = target.sum[k] + source.sum[k];
    }
    target.count += source.count;
    clusters.removeAt(bestB);
  }

  // 按各簇内最早片段的 start_time 升序重新编号。
  final List<_OrderedCluster> ordered = <_OrderedCluster>[
    for (final _Cluster cluster in clusters)
      _OrderedCluster(
        cluster: cluster,
        first: cluster.members
            .map((int m) => segments[m].startTime)
            .reduce((int a, int b) => a < b ? a : b),
      ),
  ]..sort((_OrderedCluster a, _OrderedCluster b) => a.first.compareTo(b.first));

  for (int index = 0; index < ordered.length; index++) {
    for (final int member in ordered[index].cluster.members) {
      map[segments[member].segmentId] = 'spk_${index + 1}';
    }
  }
  return map;
}

/// 全局重聚类的便捷重载：直接作用于片段列表（声纹向量缺省时用空向量，退化为保持原说话人）。
Map<String, String> globalReclusterSegments(
  List<TranscriptSegment> segments, {
  double threshold = kDefaultThreshold,
  Map<String, List<double>> vectors = const <String, List<double>>{},
}) {
  return globalRecluster(
    <ReclusterInput>[
      for (final TranscriptSegment segment in segments)
        ReclusterInput(
          segmentId: segment.segmentId,
          startTime: segment.startTime,
          vector: vectors[segment.segmentId] ?? const <double>[],
        ),
    ],
    threshold: threshold,
  );
}

/// 由片段列表构建说话人表（按首次出现顺序编号 + 分配色相下标）。
List<Speaker> buildSpeakerRoster(List<TranscriptSegment> segments, {String meetingId = ''}) {
  final Map<String, Speaker> byId = <String, Speaker>{};
  final List<TranscriptSegment> sorted = List<TranscriptSegment>.of(segments)
    ..sort(
      (TranscriptSegment a, TranscriptSegment b) {
        final int byTime = a.startTime.compareTo(b.startTime);
        return byTime != 0 ? byTime : a.segmentId.compareTo(b.segmentId);
      },
    );
  for (final TranscriptSegment segment in sorted) {
    final Speaker? existing = byId[segment.speakerId];
    if (existing != null) {
      final int first = existing.firstSeenMs < segment.startTime ? existing.firstSeenMs : segment.startTime;
      byId[segment.speakerId] = existing.copyWith(firstSeenMs: first);
      continue;
    }
    byId[segment.speakerId] = Speaker(
      meetingId: meetingId,
      speakerId: segment.speakerId,
      name: segment.speakerName ?? '发言人${byId.length + 1}',
      colorIndex: byId.length % 6,
      firstSeenMs: segment.startTime,
    );
  }
  final List<Speaker> roster = byId.values.toList(growable: false);
  return <Speaker>[
    for (int i = 0; i < roster.length; i++) roster[i].copyWith(colorIndex: i % 6),
  ];
}

/// 内部簇。
class _Cluster {
  /// 构造簇。
  _Cluster({required this.members, required this.sum, required this.count});

  /// 成员下标。
  final List<int> members;

  /// 向量和。
  final List<double> sum;

  /// 样本数。
  int count;
}

/// 排序后的簇。
class _OrderedCluster {
  /// 构造。
  const _OrderedCluster({required this.cluster, required this.first});

  /// 簇。
  final _Cluster cluster;

  /// 簇内最早片段的起始时间。
  final int first;
}
