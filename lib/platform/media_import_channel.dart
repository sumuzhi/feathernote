/// 导入音视频平台通道封装（`feathernote/media_import`）。
///
/// 契约 SSOT：`docs/IMPORT-PIPELINE-DESIGN.md` §6。
/// - `probeMedia` `{path}` → `{durationMs, hasAudio, isVideoContainer, mimeType}`；
/// - `extractAudioTrack` `{token, srcPath, destPath}` → `{path, durationMs, bytesWritten}`；
/// - `cancelExtract` `{token}` → `{cancelled}`。
///
/// 原生错误码（§6.4）→ [AppError] 映射：`E_UNSUPPORTED_CONTAINER` /
/// `E_NO_AUDIO_TRACK` / `E_CANCELLED` / `E_SRC_UNREADABLE` / `E_EXTRACT_FAILED`
/// 全部透传为 `engineCode`，用户文案随 `message` 一起由原生给出。
library;

import 'package:flutter/services.dart';

import '../core/error/app_error.dart';
import '../core/log/log.dart';

/// `probeMedia` 结果。
class MediaProbeResult {
  /// 构造探测结果。
  const MediaProbeResult({
    required this.durationMs,
    required this.hasAudio,
    required this.isVideoContainer,
    required this.mimeType,
  });

  /// 媒体时长（毫秒；取全部音视频轨的最大值）。
  final int durationMs;

  /// 是否存在音频轨。
  final bool hasAudio;

  /// 是否视频容器（存在 `video/` 轨）。
  final bool isVideoContainer;

  /// 尽力猜测的 MIME 类型（猜不出为空串）。
  final String mimeType;
}

/// `extractAudioTrack` 结果。
class MediaExtractResult {
  /// 构造分离结果。
  const MediaExtractResult({required this.path, required this.durationMs, required this.bytesWritten});

  /// 产物路径（m4a）。
  final String path;

  /// 音轨时长（毫秒）。
  final int durationMs;

  /// 写入字节数。
  final int bytesWritten;
}

/// 平台通道封装（Android Kotlin / iOS Swift 双端同名实现）。
///
/// 可注入 [MethodChannel] 便于单测（mock MethodChannel 返回值）。
class MediaImportChannel {
  /// 构造通道封装。
  MediaImportChannel({MethodChannel? channel})
    : _ch = channel ?? const MethodChannel('feathernote/media_import');

  final MethodChannel _ch;

  /// 探测媒体元信息（时长 / 音轨 / 是否视频容器）。
  ///
  /// 第二道预检（毫秒级），文件不可读抛 `E_SRC_UNREADABLE`。
  Future<MediaProbeResult> probeMedia(String path) async {
    try {
      final Object? raw = await _ch.invokeMethod<dynamic>(
        'probeMedia',
        <String, Object?>{'path': path},
      );
      final Map<Object?, Object?> map = _asMap(raw, 'probeMedia');
      return MediaProbeResult(
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        hasAudio: map['hasAudio'] == true,
        isVideoContainer: map['isVideoContainer'] == true,
        mimeType: (map['mimeType'] as String?) ?? '',
      );
    } on PlatformException catch (e) {
      throw _mapError(e, 'probeMedia');
    } on MissingPluginException {
      throw const AppError(
        ErrorCode.internal,
        '当前平台不支持导入音视频',
        engineCode: 'E_UNSUPPORTED_PLATFORM',
      );
    }
  }

  /// 分离音轨 → m4a（不解码零转码；iOS 为 AVAssetExportSession 导出）。
  ///
  /// [token] 通常为 meetingId，用于 [cancelExtract] 精确取消。
  Future<MediaExtractResult> extractAudioTrack(String token, String srcPath, String destPath) async {
    try {
      final Object? raw = await _ch.invokeMethod<dynamic>(
        'extractAudioTrack',
        <String, Object?>{'token': token, 'srcPath': srcPath, 'destPath': destPath},
      );
      final Map<Object?, Object?> map = _asMap(raw, 'extractAudioTrack');
      final String path = (map['path'] as String?) ?? destPath;
      return MediaExtractResult(
        path: path,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        bytesWritten: (map['bytesWritten'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw _mapError(e, 'extractAudioTrack');
    } on MissingPluginException {
      throw const AppError(
        ErrorCode.internal,
        '当前平台不支持导入音视频',
        engineCode: 'E_UNSUPPORTED_PLATFORM',
      );
    }
  }

  /// 取消进行中的分离任务（幂等；未在进行的 token 返回 false）。
  Future<bool> cancelExtract(String token) async {
    try {
      final Object? raw = await _ch.invokeMethod<dynamic>(
        'cancelExtract',
        <String, Object?>{'token': token},
      );
      final Map<Object?, Object?> map = _asMap(raw, 'cancelExtract');
      return map['cancelled'] == true;
    } on PlatformException catch (e) {
      // 取消本身失败不影响主流程（提取侧自有取消检查）。
      logWarn('media_import', 'cancelExtract 平台错误', <String, Object?>{'code': e.code});
      return false;
    }
  }

  /// 原生错误 → [AppError]（错误码透传，文案由原生给出，§6.4 映射表）。
  AppError _mapError(PlatformException e, String op) {
    logWarn(
      'media_import',
      '$op 平台错误',
      <String, Object?>{'code': e.code, 'message': e.message},
    );
    return AppError(ErrorCode.engineError, e.message ?? '音视频处理失败', engineCode: e.code);
  }

  /// 校验并转换通道返回的 map。
  Map<Object?, Object?> _asMap(Object? raw, String op) {
    if (raw is! Map<Object?, Object?>) {
      throw AppError(
        ErrorCode.engineError,
        '$op 返回格式异常',
        engineCode: 'E_PROTOCOL',
      );
    }
    return raw;
  }
}
