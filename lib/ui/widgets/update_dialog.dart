/// 版本更新提示弹窗。
///
/// 由启动期检查（[AppUpdateChecker]）在发现新版本时触发。设计：
/// - 标题展示远端版本号；
/// - 正文含一句引导语 +（可选）更新说明；
/// - 「立即更新」用 `url_launcher` 打开 APK 下载链接；
/// - 非强制更新提供「稍后」可关闭；强制更新（[RemoteVersion.forceUpdate] 或
///   [RemoteVersion.minVersionCode] 高于本地）则不可关闭、必须更新。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/app_update.dart';

/// 弹出版本更新提示。返回时用户已做出选择（更新或稍后）。
Future<void> showAppUpdateDialog(BuildContext context, RemoteVersion remote) async {
  final bool force = remote.forceUpdate || remote.minVersionCode > 0;
  await showDialog<void>(
    context: context,
    barrierDismissible: !force,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('发现新版本 v${remote.version}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('声羽 FeatherNote 有新版本可用，建议更新以获得更好的体验。'),
            if (remote.releaseNotes != null && remote.releaseNotes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('更新内容', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(remote.releaseNotes!),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (!force)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            final Uri uri = Uri.parse(remote.downloadUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}
