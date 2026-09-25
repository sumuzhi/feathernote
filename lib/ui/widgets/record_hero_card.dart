/// 首页待机 Hero 卡（HTML `#s01 .hero`）。
///
/// 组成：状态行 → 172px 光晕（内含 124px 橙色麦克风按钮）→ 主文案 → 副文案 →
/// 模式分段控件（可选）。App 不区分录音场景，[modes] 传空时以「能力点」
/// 静态胶囊行补位，避免按钮下方空落。
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
    required this.onMicTap,
    this.modes = const <String>[],
    this.selectedMode = 0,
    this.onModeChanged,
    this.recording = false,
    this.busy = false,
    this.busyHint,
  });

  /// 状态行主文案（待机中 / 录音中）。
  final String statusText;

  /// 状态行尾部文案（「今日已记录 42 分钟」）。
  final String statusTail;

  /// 主文案（「点击开始录音」）。
  final String title;

  /// 副文案（「中英文自动转写 · 智能区分说话人」）。
  final String subtitle;

  /// 模式文案列表（空 = 不显示分段控件，改显能力点行）。
  final List<String> modes;

  /// 选中模式下标。
  final int selectedMode;

  /// 模式切换回调。
  final ValueChanged<int>? onModeChanged;

  /// 点击麦克风回调。
  final VoidCallback onMicTap;

  /// 是否录音中（麦克风按钮呼吸光晕）。
  final bool recording;

  /// 是否「忙」（启动中 / 收尾中 / 上一段仍在生成）。
  ///
  /// 忙时麦克风按钮原地变成 spinner 且**不可点击**，并在副文案下方给出
  /// [busyHint] 说明原因 —— 而不是整页遮罩或静默禁用。
  final bool busy;

  /// 忙态原因（如「上一段正在生成纪要…」）。
  final String? busyHint;

  /// 无场景模式时的静态能力点（与设计稿副文案呼应，填补分段控件位置）。
  static const List<String> kCapabilityChips = <String>[
    '中英文转写',
    '说话人区分',
    'AI 结构化纪要',
  ];

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
          _MicButton(recording: recording, busy: busy, onTap: onMicTap),
          const SizedBox(height: 22),
          Text(title, style: AppTextStyles.cardTitle),
          const SizedBox(height: 8),
          Text(subtitle, style: AppTextStyles.meta),
          if (busy && busyHint != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              busyHint!,
              style: AppTextStyles.metaSmall,
              textAlign: TextAlign.center,
            ),
          ],
          if (modes.isNotEmpty)
            AppSegmentedControl(
              labels: modes,
              selectedIndex: selectedMode,
              onChanged: onModeChanged ?? (_) {},
            )
          else ...<Widget>[
            const SizedBox(height: 16),
            const _CapabilityChipsRow(),
          ],
        ],
      ),
    );
  }
}

/// 能力点胶囊行（无场景模式时的补位内容；窄屏自动换行）。
class _CapabilityChipsRow extends StatelessWidget {
  const _CapabilityChipsRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final String label in RecordHeroCard.kCapabilityChips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.grayWash,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: AppTextStyles.metaSmall.copyWith(color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}

/// 172px 光晕 + 124px 麦克风按钮；[busy] 时按钮原地变为 spinner 且不可点击。
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.recording,
    required this.busy,
    required this.onTap,
  });

  final bool recording;
  final bool busy;
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
              enabled: !widget.busy,
              label: widget.busy ? '正在处理，请稍候' : '开始录音',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  // busy 时不接收点击：避免上一段仍在生成时又开一段录音。
                  onTap: widget.busy ? null : widget.onTap,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: widget.busy
                        ? const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.mic_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
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
