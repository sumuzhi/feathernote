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
    this.stopping = false,
  });

  /// 是否已暂停（决定图标：暂停 ⇄ 继续）。
  final bool paused;

  /// 暂停 / 继续。
  final VoidCallback onPauseToggle;

  /// 结束并生成。
  final VoidCallback onStop;

  /// 打标记（书签）。
  final VoidCallback onBookmark;

  /// 是否正在收尾（「结束并生成」就地 loading）。
  ///
  /// 为 true 时三键全部禁用，主按钮原地变为 spinner —— 「点击生成时可以 loading」，
  /// 拿到 meetingId 后由页面跳详情页，不做整页遮罩。
  final bool stopping;

  @override
  Widget build(BuildContext context) {
    // 溢出修复：三键簇在 360dp 宽下仅剩 ~2px 余量，系统字体放大即横向溢出
    // （真机「页面右侧出现 bug」）。FittedBox 等比缩小整簇，宽屏不受影响。
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 20, AppSpacing.page, 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _SideButton(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              tooltip: paused ? '继续' : '暂停',
              onTap: stopping ? null : onPauseToggle,
            ),
            const SizedBox(width: 16),
            _StopButton(stopping: stopping, onTap: onStop),
            const SizedBox(width: 16),
            _SideButton(
              icon: Icons.bookmark_border_rounded,
              tooltip: '标记',
              onTap: stopping ? null : onBookmark,
            ),
          ],
        ),
      ),
    );
  }
}

/// 主按钮「结束并生成」：收尾时原地 spinner + 禁用。
class _StopButton extends StatelessWidget {
  const _StopButton({required this.stopping, required this.onTap});

  final bool stopping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !stopping,
      label: stopping ? '正在生成，请稍候' : '结束并生成',
      child: GestureDetector(
        onTap: stopping ? null : onTap,
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
              if (stopping)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 9),
              Text(
                stopping ? '正在生成…' : '结束并生成',
                style: AppTextStyles.button,
              ),
            ],
          ),
        ),
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

  /// 为 null 表示禁用（收尾中）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
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
          child: Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.ink : AppColors.faint,
          ),
        ),
      ),
    );
  }
}
