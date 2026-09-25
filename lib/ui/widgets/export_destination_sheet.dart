/// 导出位置选择底部弹层（默认 Download/SmartMinutes / 每次导出时选择）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/export_destination.dart';

/// 弹出位置选择；取消返回 null。
Future<ExportDestination?> showExportDestinationSheet(BuildContext context) {
  return showModalBottomSheet<ExportDestination>(
    context: context,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('导出位置', style: AppTextStyles.subHead),
            ),
          ),
          for (final ExportDestination destination in ExportDestination.values)
            ListTile(
              leading: Icon(
                destination == ExportDestination.appDownload
                    ? Icons.download_rounded
                    : Icons.drive_file_move_rounded,
                color: AppColors.orange,
              ),
              title: Text(
                destination == ExportDestination.appDownload
                    ? '默认（Download/SmartMinutes）'
                    : '每次导出时选择…',
                style: AppTextStyles.settingTitle,
              ),
              subtitle: Text(
                destination == ExportDestination.appDownload
                    ? '公共下载目录的 SmartMinutes 子文件夹，免权限直接保存'
                    : '每次导出时弹系统「另存为」，自选位置与文件名',
                style: AppTextStyles.metaSmall,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              onTap: () => Navigator.of(context).pop(destination),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
