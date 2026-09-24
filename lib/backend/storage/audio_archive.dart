/// 音频归档抽象（对应原 `server/src/services/audioStorage.js`）。
///
/// 主理人决策：**默认本地**，`CosArchive` 只留接口、不接真实 SDK。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/log/log.dart';

/// 音频归档接口。
abstract class AudioArchive {
  /// 归档模式标识（`local` / `cos`）。
  String get mode;

  /// 写入 WAV，返回 key（本地实现返回相对路径）。
  Future<String> put(String meetingId, Uint8List wav);

  /// 读取 WAV（不存在返回 null）。
  Future<Uint8List?> get(String key);

  /// 解析 key 为本地可播放路径（非本地实现可抛出 [AppError]）。
  Future<String> localPath(String key);

  /// 删除归档（不存在时静默成功）。
  Future<void> remove(String key);
}

/// 本地文件归档（默认实现）：写到 `<documents>/audio/<meetingId>.wav`。
class LocalFileArchive implements AudioArchive {
  /// 构造本地归档器；[baseDir] 为空时取 `getApplicationDocumentsDirectory()/audio`。
  LocalFileArchive({Directory? baseDir}) : _baseDirOverride = baseDir;

  /// 显式指定的根目录（测试用）。
  final Directory? _baseDirOverride;

  Directory? _cachedDir;

  @override
  String get mode => 'local';

  /// 归档根目录。
  Future<Directory> _baseDir() async {
    final Directory? cached = _cachedDir;
    if (cached != null) return cached;
    final Directory resolved = _baseDirOverride ?? Directory(p.join((await getApplicationDocumentsDirectory()).path, 'audio'));
    if (!await resolved.exists()) {
      await resolved.create(recursive: true);
    }
    _cachedDir = resolved;
    return resolved;
  }

  @override
  Future<String> put(String meetingId, Uint8List wav) async {
    final Directory dir = await _baseDir();
    final File file = File(p.join(dir.path, '$meetingId.wav'));
    await file.writeAsBytes(wav, flush: true);
    logInfo('archive', '录音已归档', <String, Object?>{'key': meetingId, 'bytes': wav.length});
    return meetingId;
  }

  @override
  Future<Uint8List?> get(String key) async {
    final File file = File(await localPath(key));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<String> localPath(String key) async {
    final Directory dir = await _baseDir();
    return p.join(dir.path, '$key.wav');
  }

  @override
  Future<void> remove(String key) async {
    final File file = File(await localPath(key));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// COS 归档（**仅接口，未实现**）。
///
/// 保留本类的意义：将来要云备份时只需替换实现，`services/` 与 `engine/` 一行不动。
/// 当前所有方法均抛 [AppError]（`engineError` + `E_NOT_IMPLEMENTED`）。
class CosArchive implements AudioArchive {
  /// 构造 COS 归档器（参数仅作占位，不发起任何网络请求）。
  CosArchive({required this.bucket, required this.region, this.prefix = 'smart-minutes/audio'});

  /// 存储桶名。
  final String bucket;

  /// 地域。
  final String region;

  /// 对象键前缀。
  final String prefix;

  @override
  String get mode => 'cos';

  AppError _notImplemented(String op) => AppError(
    ErrorCode.engineError,
    'COS 归档未实现（$op）：本轮音频归档默认本地，COS 只留接口',
    engineCode: 'E_NOT_IMPLEMENTED',
  );

  @override
  Future<String> put(String meetingId, Uint8List wav) async => throw _notImplemented('put');

  @override
  Future<Uint8List?> get(String key) async => throw _notImplemented('get');

  @override
  Future<String> localPath(String key) async => throw _notImplemented('localPath');

  @override
  Future<void> remove(String key) async => throw _notImplemented('remove');
}
