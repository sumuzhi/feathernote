/// 首页待机 Hero 卡（HTML `#s01 .hero`）。
///
/// 组成：状态行 → 172px 光晕（内含 124px 橙色麦克风按钮）→ 主文案 → 副文案 →
/// 模式分段控件（会议 / 访谈 / 灵感）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'segmented_control.dart';

/// 首页 Hero 卡。
class RecordHeroCard extends StatelessWidget {
  /// 构造 Hero 卡。
  const RecordHeroCard({
    super.key,
    required this.statusText,
    required this.statusTail,
    required this.title,
    required this.subtitle,
    required this.modes,
    required this.selectedMode,
    required this.onModeChanged,
    required this.onMicTap,
    this.recording = false,
  });

  /// 状态行主文案（待机中 / 录音中）。
  final String statusText;

  /// 状态行尾部文案（「今日已记录 42 分钟」）。
  final String statusTail;

  /// 主文案（「点击开始录音」）。
  final String title;

  /// 副文案（「中英文自动转写 · 智能区分说话人」）。
  final String subtitle;

  /// 模式文案列表。
  final List<String> modes;

  /// 选中模式下标。
  final int selectedMode;

  /// 模式切换回调。
  final ValueChanged<int> onModeChanged;

  /// 点击麦克风回调。
  final VoidCallback onMicTap;

  /// 是否录音中（麦克风按钮呼吸光晕）。
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.page, 22, AppSpacing.page, 0),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(statusText, style: AppTextStyles.meta),
              const SizedBox(width: 7),
              Text('·', style: AppTextStyles.meta),
              const SizedBox(width: 7),
              Text(statusTail, style: AppTextStyles.meta),
            ],
          ),
          const SizedBox(height: 18),
          _MicButton(recording: recording, onTap: onMicTap),
          const SizedBox(height: 22),
          Text(title, style: AppTextStyles.cardTitle),
          const SizedBox(height: 8),
          Text(subtitle, style: AppTextStyles.meta),
          AppSegmentedControl(
            labels: modes,
            selectedIndex: selectedMode,
            onChanged: onModeChanged,
          ),
        ],
      ),
    );
  }
}

/// 172px 光晕 + 124px 麦克风按钮。
class _MicButton extends StatefulWidget {
  const _MicButton({required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool animate =
        widget.recording && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }

    return SizedBox(
      width: 172,
      height: 172,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 光晕：外圈 --orange-soft，内圈（inset 24px）#FDE3CE。
          Container(
            width: 172,
            height: 172,
            decoration: const BoxDecoration(
              color: AppColors.orangeSoft,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 124,
            height: 124,
            decoration: const BoxDecoration(
              color: Color(0xFFFDE3CE),
              shape: BoxShape.circle,
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-0.34, -1),
                    end: Alignment(0.34, 1),
                    colors: <Color>[Color(0xFFF58A50), Color(0xFFEE6E2C)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0x61F0783C),
                      blurRadius: 32 + 12 * _controller.value,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Semantics(
              button: true,
              label: '开始录音',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  customBorder: const CircleBorder(),
                  child: const Center(
                    child: Icon(Icons.mic_rounded, size: 44, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
