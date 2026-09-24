/// 录音控制区（HTML `.rec-ctrl`）：暂停 / 结束并生成 / 标记。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 录音控制区。
class RecordingControls extends StatelessWidget {
  /// 构造控制区。
  const RecordingControls({
    super.key,
    required this.paused,
    required this.onPauseToggle,
    required this.onStop,
    required this.onBookmark,
  });

  /// 是否已暂停（决定图标：暂停 ⇄ 继续）。
  final bool paused;

  /// 暂停 / 继续。
  final VoidCallback onPauseToggle;

  /// 结束并生成。
  final VoidCallback onStop;

  /// 打标记（书签）。
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 20, AppSpacing.page, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _SideButton(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            tooltip: paused ? '继续' : '暂停',
            onTap: onPauseToggle,
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onStop,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: AppShadow.orangeButton,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text('结束并生成', style: AppTextStyles.button),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          _SideButton(
            icon: Icons.bookmark_border_rounded,
            tooltip: '标记',
            onTap: onBookmark,
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            boxShadow: AppShadow.card,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}
