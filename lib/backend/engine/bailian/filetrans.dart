/// 百炼离线文件转写（filetrans）：提交 / 轮询 / 下载 / 映射。
///
/// 移植 `dashscopeClient.js:237-412` 与 `realAdapters.js:47-93`。
/// 契约要点：
/// - `fileUrl` 为 `oss://` 时**必须**注入 `X-DashScope-OssResourceResolve: enable`；
/// - 说话人分离字段名是 **`diarization_enabled`**（不是 `enable_speaker_diarization`）；
/// - 轮询状态取 `subtask_status` 优先于 `task_status`；
/// - 结果 JSON 里取 `channel_id === 0`，时间戳**已是毫秒**（含秒/毫秒启发式守卫）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_error.dart';
import '../../../core/ids.dart';
import '../../../core/ws_protocol.dart';
import '../../../domain/segment.dart';
import 'bailian_endpoints.dart';

/// 提交结果。
class SubmitResult {
  /// 构造提交结果。
  const SubmitResult({required this.taskId, required this.taskStatus, required this.requestId});

  /// 百炼任务 ID。
  final String taskId;

  /// 初始状态（通常为 `PENDING`）。
  final String taskStatus;

  /// 请求 ID。
  final String requestId;
}

/// 单次轮询结果。
class PollResult {
  /// 构造轮询结果。
  const PollResult({required this.status, this.transcriptionUrl, this.message, this.raw = const <String, dynamic>{}});

  /// 归一化状态。
  final String status;

  /// 结果 JSON 的下载 URL（成功时非空）。
  final String? transcriptionUrl;

  /// 服务端消息。
  final String? message;

  /// 原始响应体。
  final Map<String, dynamic> raw;
}

/// 等待终态结果。
class WaitResult {
  /// 构造等待结果。
  const WaitResult({required this.status, this.transcriptionUrl, required this.elapsedMs});

  /// 终态（`SUCCEEDED` / `FAILED` / `TIMEOUT`）。
  final String status;

  /// 结果 URL。
  final String? transcriptionUrl;

  /// 耗时（毫秒）。
  final int elapsedMs;
}

/// filetrans 客户端（依赖可注入，单测不触网）。
class BailianFiletrans {
  /// 构造客户端。
  BailianFiletrans(this.cfg, {Dio? dio}) : _dio = dio ?? Dio();

  /// 冻结配置。
  final AppConfig cfg;

  /// HTTP 客户端。
  final Dio _dio;

  /// HTTP base。
  String get httpBase => buildHttpBase(cfg);

  /// 鉴权头。
  Map<String, String> get _authHeaders => <String, String>{
    'Authorization': 'Bearer ${cfg.dashscopeApiKey}',
    'Content-Type': 'application/json',
  };

  /// 步骤1：获取上传凭证。
  Future<Map<String, dynamic>> getUploadPolicy({String? model}) async {
    final String url = '$httpBase/api/v1/uploads?action=getPolicy&model=${Uri.encodeComponent(model ?? cfg.filetransModel)}';
    final Response<dynamic> resp = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: _authHeaders,
        receiveTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
      ),
    );
    _ensureOk(resp, '获取上传凭证');
    final Object? body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw AppError(ErrorCode.engineError, '获取上传凭证失败：响应体不是对象', engineCode: 'E_PROTOCOL');
    }
    final Object? data = body['data'];
    if (data is! Map<String, dynamic> || (data['upload_host'] as String?)?.isNotEmpty != true) {
      throw AppError(ErrorCode.engineError, '获取上传凭证失败：响应缺少 upload_host', engineCode: 'E_PROTOCOL');
    }
    return data;
  }

  /// 步骤2：上传字节到临时 OSS，返回 `oss://` URL。
  ///
  /// **字段顺序严格**（顺序错误 OSS 会 403）：
  /// `OSSAccessKeyId, Signature, policy, x-oss-object-acl, x-oss-forbid-overwrite, key, success_action_status, file`。
  Future<String> uploadBuffer(Uint8List buffer, String filename, {Map<String, dynamic>? policy}) async {
    final Map<String, dynamic> pol = policy ?? await getUploadPolicy();
    final FormData form = FormData.fromMap(<String, dynamic>{
      'OSSAccessKeyId': '${pol['oss_access_key_id']}',
      'Signature': '${pol['signature']}',
      'policy': '${pol['policy']}',
      'x-oss-object-acl': '${pol['x_oss_object_acl']}',
      'x-oss-forbid-overwrite': '${pol['x_oss_forbid_overwrite']}',
      'key': '${pol['upload_dir']}/$filename',
      'success_action_status': '200',
      'file': MultipartFile.fromBytes(buffer, filename: filename),
    });
    final Response<dynamic> resp = await _dio.post<dynamic>(
      '${pol['upload_host']}',
      data: form,
      options: Options(
        receiveTimeout: Duration(milliseconds: cfg.uploadTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.uploadTimeoutMs),
      ),
    );
    _ensureOk(resp, '临时上传');
    return buildOssUrl('${pol['upload_dir']}', filename);
  }

  /// 上传本地 WAV 文件（含大小上限校验）。
  Future<String> uploadLocalFile(String filePath, {String? model}) async {
    final File file = File(filePath);
    final int length = await file.length();
    final int maxBytes = cfg.uploadMaxMb * 1024 * 1024;
    if (length > maxBytes) {
      throw AppError(
        ErrorCode.engineError,
        '文件过大：${(length / 1024 / 1024).toStringAsFixed(1)}MB 超过上限 ${cfg.uploadMaxMb}MB，请压缩或分段',
        engineCode: 'E_TOO_LARGE',
      );
    }
    final Uint8List bytes = await file.readAsBytes();
    return uploadBuffer(bytes, filePath.split(Platform.pathSeparator).last);
  }

  /// 步骤3：提交异步转写任务。
  Future<SubmitResult> submitFiletrans(String fileUrl, {bool diarization = true, List<String>? languageHints}) async {
    final String url = '$httpBase/api/v1/services/audio/asr/transcription';
    final Map<String, String> headers = <String, String>{
      ..._authHeaders,
      'X-DashScope-Async': 'enable',
    };
    if (isOssUrl(fileUrl)) headers['X-DashScope-OssResourceResolve'] = 'enable';

    final Map<String, dynamic> body = <String, dynamic>{
      'model': cfg.filetransModel,
      'input': <String, dynamic>{
        'file_urls': <String>[fileUrl],
      },
      'parameters': <String, dynamic>{
        'channel_id': <int>[0],
        'language_hints': languageHints ?? cfg.filetransLanguageHints,
        'diarization_enabled': diarization,
      },
    };
    final Response<dynamic> resp = await _dio.post<dynamic>(
      url,
      data: body,
      options: Options(
        headers: headers,
        receiveTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
      ),
    );
    _ensureOk(resp, '提交 filetrans');
    final Object? payload = resp.data;
    if (payload is! Map<String, dynamic>) {
      throw AppError(ErrorCode.engineError, '提交 filetrans 失败：响应体不是对象', engineCode: 'E_PROTOCOL');
    }
    final Object? output = payload['output'];
    final Map<String, dynamic> out = output is Map<String, dynamic> ? output : const <String, dynamic>{};
    return SubmitResult(
      taskId: (out['task_id'] as String?) ?? '',
      taskStatus: (out['task_status'] as String?) ?? TaskStatus.pending,
      requestId: (payload['request_id'] as String?) ?? '',
    );
  }

  /// 单次轮询任务状态。
  Future<PollResult> pollTask(String taskId) async {
    final String url = '$httpBase/api/v1/tasks/${Uri.encodeComponent(taskId)}';
    final Response<dynamic> resp = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer ${cfg.dashscopeApiKey}'},
        receiveTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
        sendTimeout: Duration(milliseconds: cfg.httpTimeoutMs),
      ),
    );
    _ensureOk(resp, '轮询任务');
    final Object? payload = resp.data;
    final Map<String, dynamic> body = payload is Map<String, dynamic> ? payload : const <String, dynamic>{};
    final Object? output = body['output'];
    final Map<String, dynamic> out = output is Map<String, dynamic> ? output : const <String, dynamic>{};
    final Object? results = out['results'];
    final Map<String, dynamic> first =
        results is List && results.isNotEmpty && results[0] is Map<String, dynamic>
            ? results[0] as Map<String, dynamic>
            : const <String, dynamic>{};
    final String rawStatus = (first['subtask_status'] as String?) ?? (out['task_status'] as String?) ?? TaskStatus.pending;
    return PollResult(
      status: normalizeTaskStatus(rawStatus),
      transcriptionUrl: first['transcription_url'] as String?,
      message: (first['message'] as String?) ?? (out['message'] as String?),
      raw: body,
    );
  }

  /// 轮询直到成功 / 失败 / 超时。
  Future<WaitResult> waitTask(
    String taskId, {
    Duration? interval,
    Duration? timeout,
    void Function(String status)? onTick,
  }) async {
    final int intervalMs = (interval ?? Duration(milliseconds: cfg.filetransPollIntervalMs)).inMilliseconds;
    final int timeoutMs = (timeout ?? Duration(milliseconds: cfg.filetransTimeoutMs)).inMilliseconds;
    final Stopwatch stopwatch = Stopwatch()..start();
    for (;;) {
      final PollResult result = await pollTask(taskId);
      onTick?.call(result.status);
      if (result.status == TaskStatus.succeeded || result.status == TaskStatus.failed) {
        return WaitResult(
          status: result.status,
          transcriptionUrl: result.transcriptionUrl,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
      if (stopwatch.elapsedMilliseconds >= timeoutMs) {
        return WaitResult(status: TaskStatus.timeout, transcriptionUrl: null, elapsedMs: stopwatch.elapsedMilliseconds);
      }
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }

  /// 下载 `transcription_url`（公网 JSON，24h 有效）→ 解析对象。
  Future<Map<String, dynamic>> downloadTranscription(String url) async {
    final Response<dynamic> resp = await _dio.get<dynamic>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
      ),
    );
    _ensureOk(resp, '下载转写结果');
    final Object? body = resp.data;
    if (body is Map<String, dynamic>) return body;
    if (body is String) {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw AppError(ErrorCode.engineError, '下载转写结果失败：响应不是合法 JSON', engineCode: 'E_PROTOCOL');
  }

  /// 全链路编排：本地 WAV → `oss://` → 提交 → 轮询 → 下载 → 返回原始 JSON。
  Future<({Map<String, dynamic> raw, String ossUrl, String taskId})> transcribeLocalAudio(
    String wavPath, {
    bool diarization = true,
    Duration? interval,
    Duration? timeout,
    void Function(String status)? onProgress,
  }) async {
    final String ossUrl = await uploadLocalFile(wavPath);
    final SubmitResult submitted = await submitFiletrans(ossUrl, diarization: diarization);
    final String taskId = submitted.taskId;
    final WaitResult polled = await waitTask(
      taskId,
      interval: interval,
      timeout: timeout,
      onTick: onProgress,
    );
    if (polled.status != TaskStatus.succeeded || polled.transcriptionUrl == null) {
      throw AppError(
        ErrorCode.engineError,
        'filetrans 未成功（status=${polled.status}）',
        engineCode: polled.status == TaskStatus.timeout ? 'E_TIMEOUT' : 'E_TASK_FAILED',
      );
    }
    final Map<String, dynamic> raw = await downloadTranscription(polled.transcriptionUrl!);
    return (raw: raw, ossUrl: ossUrl, taskId: taskId);
  }

  /// 状态码校验（统一错误分类）。
  void _ensureOk(Response<dynamic> resp, String stage) {
    final int? status = resp.statusCode;
    if (status == null || status < 200 || status >= 300) {
      throw AppError.fromStatus(status ?? 0, '$stage 失败（HTTP $status）');
    }
  }
}

/// 把百炼 transcription JSON 映射为本项目片段列表（移植 `mapFiletransToSegments`）。
///
/// 规则：
/// 1. 取 `channel_id === 0` 的通道（缺则取第一个通道）；
/// 2. 丢弃空文本句子；
/// 3. 时间戳**已是毫秒** → 直取（含秒/毫秒启发式守卫：duration/maxEnd > 50 判定为秒）；
/// 4. 说话人按**首次出现顺序**重排为 `spk_1..n`；
/// 5. 一句 = 一个片段，`segment_id` 从 1 连续编号，`confidence = 0.9`；
/// 6. `seq_start/seq_end` 与 20ms 帧对齐。
List<TranscriptSegment> mapFiletransToSegments(
  Map<String, dynamic> raw, {
  int frameMs = 20,
  String meetingId = '',
}) {
  final int unit = frameMs > 0 ? frameMs : 20;
  final Object? transcripts = raw['transcripts'];
  final List<Object?> list = transcripts is List ? transcripts : const <Object?>[];
  Map<String, dynamic>? channel;
  for (final Object? item in list) {
    if (item is Map<String, dynamic>) {
      if (item['channel_id'] == 0) {
        channel = item;
        break;
      }
      channel ??= item;
    }
  }
  final Object? sentences = channel?['sentences'];
  final List<Map<String, dynamic>> usable = <Map<String, dynamic>>[];
  if (sentences is List) {
    for (final Object? item in sentences) {
      if (item is Map<String, dynamic>) {
        final String text = (item['text'] as String?) ?? '';
        if (text.trim().isNotEmpty) usable.add(item);
      }
    }
  }
  if (usable.isEmpty) return const <TranscriptSegment>[];

  // 时间戳单位启发式守卫：仅当 duration/最大结束时间 比值 > 50 时判定为「秒」。
  final double? durationMs = _asDouble(raw['properties'] is Map ? (raw['properties'] as Map)['original_duration_in_milliseconds'] : null);
  double maxEnd = 0;
  for (final Map<String, dynamic> sentence in usable) {
    final double value = _asDouble(sentence['end_time']) ?? 0;
    if (value > maxEnd) maxEnd = value;
  }
  final double scale = (durationMs != null && durationMs > 0 && maxEnd > 0 && durationMs / maxEnd > 50) ? 1000 : 1;

  // 按首次出现顺序（最小 begin_time 升序；并列时原 speaker_id 数值升序）重排说话人。
  final Map<String, double> minBegin = <String, double>{};
  for (final Map<String, dynamic> sentence in usable) {
    final String key = '${sentence['speaker_id'] ?? ''}';
    final double begin = (_asDouble(sentence['begin_time']) ?? 0) * scale;
    if (!minBegin.containsKey(key) || begin < minBegin[key]!) {
      minBegin[key] = begin;
    }
  }
  final List<MapEntry<String, double>> ranked = minBegin.entries.toList()
    ..sort((MapEntry<String, double> a, MapEntry<String, double> b) {
      final int byTime = a.value.compareTo(b.value);
      if (byTime != 0) return byTime;
      return (_asDouble(a.key) ?? 0).compareTo(_asDouble(b.key) ?? 0);
    });
  final Map<String, int> speakerRank = <String, int>{
    for (int i = 0; i < ranked.length; i++) ranked[i].key: i,
  };

  return <TranscriptSegment>[
    for (int index = 0; index < usable.length; index++)
      _segmentFromSentence(usable[index], index, speakerRank, scale, unit, meetingId),
  ];
}

TranscriptSegment _segmentFromSentence(
  Map<String, dynamic> sentence,
  int index,
  Map<String, int> speakerRank,
  double scale,
  int frameMs,
  String meetingId,
) {
  final int beginRaw = (_asDouble(sentence['begin_time']) ?? 0 * scale).round();
  final int startTime = beginRaw < 0 ? 0 : beginRaw;
  final int endRaw =
      sentence['end_time'] == null ? beginRaw : (_asDouble(sentence['end_time'])! * scale).round();
  final int endTime = endRaw > startTime ? endRaw : startTime;
  final String key = '${sentence['speaker_id'] ?? ''}';
  final int rank = speakerRank[key] ?? 0;
  final int seqStart = startTime ~/ frameMs;
  final int seqEnd = ((endTime / frameMs).ceil() - 1) > seqStart ? ((endTime / frameMs).ceil() - 1) : seqStart;
  return TranscriptSegment(
    meetingId: meetingId,
    segmentId: 'seg_${index + 1}',
    ordinal: index,
    speakerId: 'spk_${rank + 1}',
    text: (sentence['text'] as String?) ?? '',
    startTime: startTime,
    endTime: endTime,
    confidence: kFiletransConfidence,
    seqStart: seqStart,
    seqEnd: seqEnd,
  );
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
