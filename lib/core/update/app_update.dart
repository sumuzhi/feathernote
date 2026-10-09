/// 启动期版本更新检查。
///
/// 设计：App 启动后拉取远端 `version.json`（[AppConfig.updateManifestUrl]），
/// 与本地 `versionCode`（来自 `package_info_plus`）比较。远端更高、或远端要求的最低
/// 版本高于本地 → 判定需要更新，由 UI 层弹窗提示。
///
/// 失败语义：清单不可达 / 解析失败 / 字段缺失，**一律静默返回不需要更新**，绝不在
/// 启动路径抛错或阻断用户。这与主理人「错误分支不静默脏数据但要友好」的口径一致——
/// 更新提示是增强项，不是启动前置条件。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../log/log.dart';

/// 远端版本清单（version.json 的字段映射）。
class RemoteVersion {
  /// 构造远端版本。
  const RemoteVersion({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.buildStamp,
    this.releaseNotes,
    this.forceUpdate = false,
    this.minVersionCode = 0,
  });

  /// 从 JSON 解析（字段缺失时给安全默认值，不抛错）。
  factory RemoteVersion.fromJson(Map<String, dynamic> json) {
    return RemoteVersion(
      version: json['version'] as String? ?? '',
      versionCode: (json['versionCode'] as num? ?? 0).toInt(),
      downloadUrl: json['downloadUrl'] as String? ?? '',
      buildStamp: json['buildStamp'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      minVersionCode: (json['minVersionCode'] as num? ?? 0).toInt(),
    );
  }

  /// 远端展示版本号（如 `1.0.1`）。
  final String version;

  /// 远端 versionCode（用于与本地比较的整数）。
  final int versionCode;

  /// APK 下载地址（https）。
  final String downloadUrl;

  /// 构建戳（与下载页/App 设置页核对用）。
  final String? buildStamp;

  /// 更新说明（支持多行文本）。
  final String? releaseNotes;

  /// 是否强制更新（强制时弹窗不可关闭，必须更新）。
  final bool forceUpdate;

  /// 远端要求的最低本地 versionCode：高于本地即视为「必须更新」。
  final int minVersionCode;
}

/// 更新判定结果。
class UpdateDecision {
  /// 构造判定结果。
  const UpdateDecision({required this.available, this.remote});

  /// 是否有可用更新。
  final bool available;

  /// 远端版本（available 为 true 时非 null）。
  final RemoteVersion? remote;
}

/// 纯函数：本地 versionCode 是否需要更新到 [remote]。
///
/// 判定规则（与 manifest 字段一一对应）：
/// - [remote.versionCode] <= 0 或下载地址为空 → 清单无效，不更新；
/// - 远端 versionCode 高于本地 → 更新；
/// - 远端要求的最低版本 [remote.minVersionCode] 高于本地 → 更新（即便远端版本号恰好相等）。
bool needsUpdate(int localVersionCode, RemoteVersion remote) {
  if (remote.versionCode <= 0 || remote.downloadUrl.isEmpty) return false;
  return remote.versionCode > localVersionCode ||
      (remote.minVersionCode > 0 && remote.minVersionCode > localVersionCode);
}

/// 版本更新检查器。
///
/// 网络与本地版本读取均**可注入**，便于单测（默认走 Dio + `PackageInfo.fromPlatform`）。
/// [check] 失败时返回 `available=false`，不向上抛。
class AppUpdateChecker {
  /// 构造检查器。
  AppUpdateChecker({
    required this.manifestUrl,
    this.fetch,
    this.localVersionCodeProvider,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  /// 远端清单地址。
  final String manifestUrl;

  /// 可注入的拉取函数（单测用）；为空则走默认 Dio GET。
  final Future<Map<String, dynamic>> Function(String url)? fetch;

  /// 可注入的本地 versionCode 读取（单测用）；为空则读 `PackageInfo.fromPlatform`。
  final Future<int> Function()? localVersionCodeProvider;

  final Dio _dio;

  Future<Map<String, dynamic>> _doFetch(String url) async {
    final Response<dynamic> resp = await _dio.get<dynamic>(
      url,
      options: Options(
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    return _asMap(resp.data);
  }

  Future<int> _readLocal() async {
    if (localVersionCodeProvider != null) return localVersionCodeProvider!();
    final PackageInfo info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 拉取清单并比较，返回是否需要更新。
  ///
  /// 任意异常（网络/解析/字段缺失）都被吞掉并返回 `available=false`，
  /// 保证启动路径不被更新检查拖垮。
  Future<UpdateDecision> check() async {
    try {
      final Map<String, dynamic> data =
          fetch != null ? await fetch!(manifestUrl) : await _doFetch(manifestUrl);
      final RemoteVersion remote = RemoteVersion.fromJson(data);
      final int local = await _readLocal();
      final bool need = needsUpdate(local, remote);
      if (need) {
        logInfo(
          'update',
          '检测到新版本 remote=${remote.version}(${remote.versionCode}) '
          'local=$local → 提示更新',
        );
      }
      return UpdateDecision(available: need, remote: remote);
    } catch (e) {
      logWarn('update', '版本检查失败（已忽略，不阻断启动）：$e');
      return const UpdateDecision(available: false);
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 忽略解析失败，交由上层返回 available=false。
      }
    }
    return <String, dynamic>{};
  }
}
