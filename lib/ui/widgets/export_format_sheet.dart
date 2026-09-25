/// 导出格式选择底部弹层（Markdown / PDF / Word / TXT）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/exporter.dart';

/// 弹出格式选择；取消返回 null。
Future<ExportFormat?> showExportFormatSheet(BuildContext context) {
  return showModalBottomSheet<ExportFormat>(
    context: context,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
            child: Row(
              children: <Widget>[
                Text('选择导出格式', style: AppTextStyles.subHead),
              ],
            ),
          ),
          for (final ExportFormat format in ExportFormat.values)
            ListTile(
              leading: Icon(_iconOf(format), color: AppColors.orange),
              title: Text(format.label, style: AppTextStyles.settingTitle),
              subtitle: Text(format.hint, style: AppTextStyles.metaSmall),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              onTap: () => Navigator.of(context).pop(format),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

IconData _iconOf(ExportFormat format) => switch (format) {
      ExportFormat.markdown => Icons.code_rounded,
      ExportFormat.pdf => Icons.picture_as_pdf_rounded,
      ExportFormat.word => Icons.description_rounded,
      ExportFormat.txt => Icons.text_snippet_rounded,
    };
