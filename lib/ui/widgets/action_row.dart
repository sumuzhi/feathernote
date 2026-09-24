/// 录音态操作行（设计稿 02 号屏 / 2:195）。
///
/// 三键：`暂停/继续`（白底圆形）· `结束并生成`（橙色 pill）· `书签`（白底圆形）。
/// **不是** Web 版那条置底操作条。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';

/// 录音操作行。
class ActionRow extends StatelessWidget {
  /// 构造操作行。
  const ActionRow({
    super.key,
    required this.paused,
    required this.onTogglePause,
    required this.onFinish,
    required this.onBookmark,
    this.busy = false,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.page),
  });

  /// 是否已暂停。
  final bool paused;

  /// 暂停 / 继续回调。
  final VoidCallback onTogglePause;

  /// 结束并生成回调。
  final VoidCallback onFinish;

  /// 书签回调。
  final VoidCallback onBookmark;

  /// 结束流程进行中（禁用）。
  final bool busy;

  /// 外边距。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          AppIconFab(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: busy ? null : onTogglePause,
            tooltip: paused ? '继续录音' : '暂停录音',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppPrimaryButton(
              label: '结束并生成',
              icon: Icons.stop_rounded,
              onPressed: busy ? null : onFinish,
              busy: busy,
            ),
          ),
          const SizedBox(width: 12),
          AppIconFab(
            icon: Icons.bookmark_border_rounded,
            onTap: busy ? null : onBookmark,
            tooltip: '添加书签',
          ),
        ],
      ),
    );
  }
}
