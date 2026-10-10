/// App 内下载并安装更新。
///
/// 替代原来「跳浏览器手动下载」的体验：点击「立即更新」后，App 内用 Dio 下载 APK
/// （带进度 / 可取消），下载完成后通过原生通道 [MethodChannel] 调起 Android 包安装器。
///
/// 失败兜底：原生通道不可用 / 安装权限被拒 / 下载异常时，回退为打开下载链接由浏览器接管，
/// 保证「更新」入口永远能把用户带向新版，绝不卡死。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';

/// 原生 APK 安装通道名（与 android 侧 [ApkInstallerPlugin] 保持一致）。
const String _kApkInstallerChannel = 'com.feathernote.app/apk_installer';

/// 本地落盘的更新包文件名（位于应用私有 files/updates/，FileProvider 授权范围内）。
const String _kUpdateApkName = 'feathernote-update.apk';

/// 在 App 内下载 [remote] 指向的 APK 并调起安装。
///
/// 该函数**不向上抛异常**：所有错误路径都以回退（浏览器下载）或提示呈现，
/// 保证更新入口永远可用。
Future<void> downloadAndInstallUpdate(BuildContext context, RemoteVersion remote) async {
  if (!context.mounted) return;

  final Dio dio = Dio();
  final ValueNotifier<double?> progress = ValueNotifier<double?>(0);
  final CancelToken cancelToken = CancelToken();
  bool cancelled = false;
  BuildContext? dialogCtx;

  // 落盘路径：应用私有 files/updates/（FileProvider 授权范围，无需存储权限）。
  final Directory supportDir = await getApplicationSupportDirectory();
  final Directory updatesDir = Directory(p.join(supportDir.path, 'updates'));
  if (!updatesDir.existsSync()) updatesDir.createSync(recursive: true);
  final File apkFile = File(p.join(updatesDir.path, _kUpdateApkName));
  if (apkFile.existsSync()) apkFile.deleteSync();

  // 启动下载（不 await —— 进度驱动进度弹窗）。
  final Future<void> downloadFuture = dio
      .download(
        remote.downloadUrl,
        apkFile.path,
        cancelToken: cancelToken,
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onReceiveProgress: (int received, int total) {
          progress.value = total > 0 ? received / total : null;
        },
      )
      .then((_) {
        progress.value = 1;
        if (dialogCtx != null && dialogCtx!.mounted) Navigator.of(dialogCtx!).pop(true);
      });

  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      dialogCtx = ctx;
      return _DownloadDialog(
        progress: progress,
        onCancel: () {
          cancelled = true;
          cancelToken.cancel('user-cancel');
          if (dialogCtx != null && dialogCtx!.mounted) Navigator.of(dialogCtx!).pop(false);
        },
      );
    },
  );
  if (cancelled) return;

  // 等待下载真正结束：成功已在 then 里 pop；取消 / 错误在此统一回退。
  try {
    await downloadFuture;
  } on DioException catch (e) {
    if (!CancelToken.isCancel(e)) _fallbackToBrowser(context, remote);
    return;
  } catch (_) {
    _fallbackToBrowser(context, remote);
    return;
  }

  // 文件校验：存在且尺寸合理（< 1MB 视为下载残缺）。
  if (!apkFile.existsSync() || apkFile.lengthSync() < 1024 * 1024) {
    _fallbackToBrowser(context, remote);
    return;
  }

  await _installApk(context, apkFile.path, remote);
}

/// 通过原生通道调起 Android 包安装器。
///
/// 前置：检查 [canInstallPackages]；无权限则跳转系统设置页引导用户开启，返回后由用户
/// 再次点击更新。安装通道异常时回退浏览器下载。
Future<void> _installApk(BuildContext context, String apkPath, RemoteVersion remote) async {
  final MethodChannel channel = MethodChannel(_kApkInstallerChannel);
  try {
    final bool canInstall = await channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) {
      await channel.invokeMethod<void>('requestInstallPermission');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('请在系统设置中允许「声羽」安装未知应用，然后重新点击更新'),
          duration: Duration(seconds: 4),
        ));
      }
      return;
    }
    await channel.invokeMethod<void>('installApk', <String, String>{'path': apkPath});
  } on PlatformException {
    _fallbackToBrowser(context, remote);
  }
}

/// 无法在 App 内完成时，回退为打开下载链接由浏览器接管。
Future<void> _fallbackToBrowser(BuildContext context, RemoteVersion remote) async {
  if (!context.mounted) return;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('无法在应用内完成更新，已改用浏览器下载'),
      duration: Duration(seconds: 3),
    ));
  }
  final Uri uri = Uri.parse(remote.downloadUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 下载进度弹窗（LinearProgressIndicator + 百分比 + 取消）。
class _DownloadDialog extends StatelessWidget {
  /// 构造下载进度弹窗。
  const _DownloadDialog({required this.progress, required this.onCancel});

  /// 进度（null = 不确定 / 准备中）。
  final ValueNotifier<double?> progress;

  /// 取消回调。
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在下载更新'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (BuildContext ctx, double? value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (value == null)
              const LinearProgressIndicator()
            else
              LinearProgressIndicator(value: value),
            const SizedBox(height: 8),
            Text(value == null ? '准备中…' : '${(value * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: onCancel, child: const Text('取消')),
      ],
    );
  }
}
