/// 屏 15：上传 · 处理中（视频分离音轨）（HTML 设计稿屏 15，画布 390×844）。
///
/// 逐元素对照 `15 · 上传 · 处理中（视频分离音轨）/index.html`：
/// 顶栏（返回 / 「处理中」/「后台处理」）→ 文件信息卡（图标 + 文件名 + meta +
/// 「视频」角标）→ 整体进度卡（标题 + 百分比 + 进度条 + 预计提示）→ 四步卡
/// （①上传 ②分离音轨 ③语音转写 ④AI 生成纪要）→ 说明条 → 底部双按钮。
///
/// 四步卡四种状态（HTML 只画了 done / running / idle，failed 为按同视觉语言
/// 外推：浅红底 + 红色 ✕，见 [_StepIcon]）：
/// - done：20×20 `#E9F3ED` 圆 + `#4E9A6A` 勾；
/// - running：`#FDEEE2` 底环 + `#F0783C` 转圈弧（[CircularProgressIndicator]）；
/// - idle：20×20 `#F1E7DC` 圆 + 6×6 `#C2A08C` 圆心；
/// - failed：`#E5483C` @12% 底 + `#E5483C` ✕。
///
/// HTML 屏 15 没有底部 TabBar（内容区 782 = 844 − 62 撑满整屏），
/// 因此本屏不渲染 TabBar；`onTabTap` / `selectedTab` 仅为保持调用方契约。
/// 顶部状态栏（9:41 / 信号 / 电量）是画布产物，不还原（见 `screen_frame.dart`）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/import_design.dart';
import '../utils/design_scale.dart';
import 'screen_frame.dart';

/// 单步卡视图数据。
class ImportStepView {
  /// 构造步骤卡数据。
  const ImportStepView({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.status,
    this.percent,
    this.skip = false,
  });

  /// 序号（1-4）。
  final int index;

  /// 标题（上传 / 分离音轨 / 语音转写 / 纪要生成）。
  final String title;

  /// 副文案。
  final String subtitle;

  /// 状态（`idle` / `running` / `done` / `failed` / `cancelled` / `skip`）。
  final String status;

  /// 上传进度 0..1（仅步骤 ①/②）。
  final double? percent;

  /// 是否「无需分离」占位。
  final bool skip;

  /// 是否已完成。
  bool get done => status == 'done';

  /// 是否进行中。
  bool get running => status == 'running';

  /// 是否失败（含已取消）。
  bool get failed => status == 'failed' || status == 'cancelled';

  /// 主状态文案（屏幕阅读器 / 失败态尾标）。
  String get statusLabel => switch (status) {
        'running' => '处理中…',
        'done' => '完成',
        'failed' => '失败',
        'cancelled' => '已取消',
        'skip' => '无需分离',
        _ => '等待中',
      };
}

/// 屏 15 视觉。
class ImportProcessingScreen extends StatelessWidget {
  /// 构造屏 15。
  const ImportProcessingScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isVideo,
    required this.steps,
    required this.allDone,
    this.failureReason,
    required this.onBack,
    required this.onCancel,
    required this.onViewMinutes,
    this.onTabTap,
    this.selectedTab = 0,
  });

  /// 标题（文件名）。
  final String title;

  /// 副标题（来源说明）。
  final String subtitle;

  /// 是否视频（决定文件卡角标与说明条文案）。
  final bool isVideo;

  /// 四步卡数据。
  final List<ImportStepView> steps;

  /// 四步是否全部完成。
  final bool allDone;

  /// 失败原因（仅在导入失败态展示；非失败为 null，不渲染，避免反复出现/隐藏抖动）。
  final String? failureReason;

  /// 「后台处理」（顶栏右上 = 橙色主按钮）。
  final VoidCallback onBack;

  /// 「取消处理」/「关闭」。
  final VoidCallback onCancel;

  /// 「查看纪要」（完成后）。
  final VoidCallback onViewMinutes;

  /// 底部 Tab 点击（HTML 屏 15 无 TabBar，保留入参以兼容调用方）。
  final ValueChanged<int>? onTabTap;

  /// 选中 Tab（HTML 屏 15 无 TabBar，保留入参以兼容调用方）。
  final int selectedTab;

  @override
  Widget build(BuildContext context) {
    final bool failed = steps.any((ImportStepView s) => s.failed);
    final double percent = _overallPercent(steps);
    return ScreenFrame(
      bottomSpacer: s(context, 24) + s(context, 48) + s(context, 16),
      bottomCta: _ButtonRow(
        allDone: allDone,
        failed: failed,
        onBack: onBack,
        onCancel: onCancel,
        onViewMinutes: onViewMinutes,
      ),
      // 固定头部：顶栏 + 其上 4、其下 16 的间距一起挪出滚动区，顶栏与文件卡的
      // 视觉间距仍是 16（与改前一致）。右上「后台处理」随时可点。
      header: Padding(
        padding: EdgeInsets.symmetric(horizontal: s(context, 20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: s(context, 4)),
            _TopBar(
              title: allDone ? '导入完成' : (failed ? '导入失败' : '处理中'),
              onBack: onBack,
            ),
            SizedBox(height: s(context, 16)),
          ],
        ),
      ),
      body: Padding(
        // HTML 内容区 padding: 4px 20px 24px（顶部 4 已随 header 一起给到顶栏）。
        padding: EdgeInsets.symmetric(horizontal: s(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _FileCard(title: title, subtitle: subtitle, isVideo: isVideo),
            SizedBox(height: s(context, 16)),
            _OverallCard(percent: percent, failureReason: failureReason),
            SizedBox(height: s(context, 16)),
            _StepsCard(steps: steps),
            SizedBox(height: s(context, 16)),
            _NoteCard(isVideo: isVideo),
          ],
        ),
      ),
    );
  }
}

/// 顶栏：返回箭头 + 「处理中」+「后台处理」（350×44）。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final double tap = s(context, 44);
    return SizedBox(
      height: s(context, 44),
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // Back：设计稿箭头 6.5×11 `#C2A08C`，中心 (9.25, 22)。
          Positioned(
            left: s(context, 9.25) - tap / 2,
            top: s(context, 22) - tap / 2,
            width: tap,
            height: tap,
            child: Semantics(
              button: true,
              label: '返回',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: s(context, 20),
                  color: ImportDesign.chevron,
                ),
              ),
            ),
          ),
          Positioned(
            left: s(context, 50),
            top: s(context, 9.5),
            height: s(context, 25),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: ImportDesign.ts(
                  context,
                  17,
                  FontWeight.w700,
                  AppColors.ink,
                  lineHeight: ImportDesign.lh17,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // 「后台处理」：设计稿 51×25 右对齐，命中区向左扩到 67×44。
          Positioned(
            right: 0,
            top: 0,
            width: s(context, 67),
            height: s(context, 44),
            child: Semantics(
              button: true,
              label: '后台处理',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '后台处理',
                    style: ImportDesign.ts(context, 13, FontWeight.w500, AppColors.orange),
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

/// 文件信息卡（350 宽，圆角 18，padding 14，白底 + 暖棕阴影）。
class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.title,
    required this.subtitle,
    required this.isVideo,
  });

  final String title;
  final String subtitle;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(s(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(s(context, 18)),
        boxShadow: ImportDesign.cardShadow(context),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: s(context, 44),
            height: s(context, 44),
            decoration: BoxDecoration(
              color: isVideo ? ImportDesign.videoSoft : ImportDesign.audioSoft,
              borderRadius: BorderRadius.circular(s(context, 13)),
            ),
            alignment: Alignment.center,
            child: Icon(
              isVideo ? Icons.video_file_rounded : Icons.audio_file_rounded,
              size: s(context, 22),
              color: isVideo ? ImportDesign.videoInk : ImportDesign.orangeText,
            ),
          ),
          SizedBox(width: s(context, 12)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: ImportDesign.ts(
                    context,
                    14,
                    FontWeight.w600,
                    AppColors.ink,
                    lineHeight: ImportDesign.lh14File,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: s(context, 4)),
                Text(
                  subtitle,
                  style: ImportDesign.ts(
                    context,
                    11,
                    FontWeight.w400,
                    AppColors.muted,
                    lineHeight: ImportDesign.lh11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: s(context, 12)),
          _KindChip(isVideo: isVideo),
        ],
      ),
    );
  }
}

/// 「视频」/「音频」角标（38×24，圆角 9）。
class _KindChip extends StatelessWidget {
  const _KindChip({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: s(context, 38),
      height: s(context, 24),
      decoration: BoxDecoration(
        color: isVideo ? ImportDesign.videoSoft : ImportDesign.audioSoft,
        borderRadius: BorderRadius.circular(s(context, 9)),
      ),
      alignment: Alignment.center,
      child: Text(
        isVideo ? '视频' : '音频',
        style: ImportDesign.ts(
          context,
          11,
          FontWeight.w500,
          isVideo ? ImportDesign.videoInk : ImportDesign.orangeText,
          lineHeight: ImportDesign.lh11,
        ),
      ),
    );
  }
}

/// 整体进度卡（350 宽，圆角 20，padding 18/16，gap 12）。
///
/// 稳定渲染「整体进度 + 百分比 + 进度条」三项，**不再在下方追加随处理进度
/// 反复出现/隐藏的 ETA tips**（旧实现里「预计还需约 X 分钟」会随 etaMinutes
/// 在 0 ↔ >0 间闪现，导致卡片高度跳动、整页内容上下抖动，产品反馈已剔除）。
///
/// 仅当 [failureReason] 非空（导入失败态）时，在进度条下方追加一行失败原因——
/// 这是一次性的静态展示（进入失败态才出现），不会在处理过程中反复闪现，因此
/// 不会引发抖动，同时保留失败诊断信息（详见类级说明 / issue ③ 修复边界）。
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.percent, this.failureReason});

  final double percent;

  /// 失败原因（仅失败态非空；处理中/完成态为 null 不渲染）。
  final String? failureReason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: s(context, 18),
        vertical: s(context, 16),
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(s(context, 20)),
        boxShadow: ImportDesign.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '整体进度',
                style: ImportDesign.ts(context, 13, FontWeight.w600, AppColors.ink),
              ),
              Text(
                '${(percent.clamp(0.0, 1.0) * 100).round()}%',
                style: ImportDesign.ts(
                  context,
                  15,
                  FontWeight.w600,
                  AppColors.orange,
                  lineHeight: ImportDesign.lh15Pct,
                ),
              ),
            ],
          ),
          SizedBox(height: s(context, 12)),
          _ProgressBar(
            height: s(context, 8),
            radius: s(context, 4),
            percent: percent,
          ),
          if (failureReason != null) ...<Widget>[
            SizedBox(height: s(context, 10)),
            Text(
              failureReason!,
              style: ImportDesign.ts(
                context,
                11,
                FontWeight.w400,
                AppColors.red,
                lineHeight: ImportDesign.lh11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// 进度条（底轨 ` #F1E7DC`，填充 `#F0783C`，宽度按百分比占满可用宽）。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.height,
    required this.radius,
    required this.percent,
  });

  final double height;
  final double radius;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final double value = percent.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: ImportDesign.track,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: value <= 0
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: width * value,
                    height: height,
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// 四步卡（350 宽，圆角 20，padding 18，步间 gap 14）。
///
/// HTML 的 StepsCard 里**没有**小标题行，第一行就是步骤 ①。
class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.steps});

  final List<ImportStepView> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(s(context, 18)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(s(context, 20)),
        boxShadow: ImportDesign.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < steps.length; i++) ...<Widget>[
            if (i > 0) SizedBox(height: s(context, 14)),
            _StepRow(step: steps[i]),
          ],
        ],
      ),
    );
  }
}

/// 单步行（314 宽，row gap 12，align center）。
class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final ImportStepView step;

  @override
  Widget build(BuildContext context) {
    final Widget? trailing;
    if (step.running && step.percent != null) {
      trailing = Text(
        '${(step.percent!.clamp(0.0, 1.0) * 100).round()}%',
        style: ImportDesign.ts(context, 12, FontWeight.w600, AppColors.orange),
      );
    } else if (step.failed) {
      trailing = Text(
        step.statusLabel,
        style: ImportDesign.ts(context, 12, FontWeight.w600, AppColors.red),
      );
    } else if (step.skip) {
      trailing = Text(
        '无需分离',
        style: ImportDesign.ts(
          context,
          11,
          FontWeight.w400,
          AppColors.muted,
          lineHeight: ImportDesign.lh11,
        ),
      );
    } else {
      // HTML 已完成步的尾标是耗时（如「00:12」），本项目的视图数据里没有
      // 单步耗时，故留空，不臆造数值。
      trailing = null;
    }
    // HTML：进行中的步 Col 内间距 5，其余 3；进度条在**副文案下方**（stretch 到
    // Col 宽度，比整体进度条窄）。
    final bool withBar = step.running && step.percent != null;
    final double colGap = withBar ? s(context, 5) : s(context, 3);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _StepIcon(step: step),
        SizedBox(width: s(context, 12)),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                step.title,
                style: ImportDesign.ts(
                  context,
                  13,
                  FontWeight.w600,
                  step.done || step.running || step.failed
                      ? AppColors.ink
                      : AppColors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: colGap),
              // 设计稿的副文案都是单行；用 FittedBox 轻缩代替省略号，保住文案完整。
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  step.subtitle,
                  style: ImportDesign.ts(
                    context,
                    11,
                    FontWeight.w400,
                    step.done || step.running || step.failed
                        ? AppColors.muted
                        : const Color(0xFFB9A695),
                    lineHeight: ImportDesign.lh11,
                  ),
                  maxLines: 1,
                ),
              ),
              if (withBar) ...<Widget>[
                SizedBox(height: colGap),
                _ProgressBar(
                  height: s(context, 4),
                  radius: s(context, 2),
                  percent: step.percent!,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          SizedBox(width: s(context, 12)),
          trailing,
        ],
      ],
    );
  }
}

/// 步骤状态图标（24×24 命中盒，内部 20×20 圆 / 转圈）。
class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.step});

  final ImportStepView step;

  @override
  Widget build(BuildContext context) {
    final double box = s(context, 24);
    final double circle = s(context, 20);
    if (step.running) {
      // 进行中：`#FDEEE2` 底环 + `#F0783C` 转圈弧（stroke 2.6）。
      return SizedBox(
        width: box,
        height: box,
        child: CircularProgressIndicator(
          strokeWidth: s(context, 2.6),
          backgroundColor: ImportDesign.stepRingBg,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
        ),
      );
    }
    if (step.done) {
      return SizedBox(
        width: box,
        height: box,
        child: Center(
          child: Container(
            width: circle,
            height: circle,
            decoration: const BoxDecoration(
              color: ImportDesign.stepDoneBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              size: s(context, 14),
              color: ImportDesign.stepDoneInk,
            ),
          ),
        ),
      );
    }
    if (step.failed) {
      // 外推：HTML 只画了 done / running / idle 三种，失败态沿用「浅底 + 主色
      // 字形」的语言，取项目里的录音红 `#E5483C`。
      return SizedBox(
        width: box,
        height: box,
        child: Center(
          child: Container(
            width: circle,
            height: circle,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.close_rounded,
              size: s(context, 14),
              color: AppColors.red,
            ),
          ),
        ),
      );
    }
    // idle / skip：20×20 `#F1E7DC` 圆 + 6×6 `#C2A08C` 圆心。
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: Container(
          width: circle,
          height: circle,
          decoration: const BoxDecoration(
            color: ImportDesign.stepIdleBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: s(context, 6),
            height: s(context, 6),
            decoration: const BoxDecoration(
              color: ImportDesign.stepIdleDot,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 说明条（350 宽，圆角 14，`#FFF0E3` 底，信息图标 + 单行灰字）。
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: s(context, 14),
        vertical: s(context, 11),
      ),
      decoration: BoxDecoration(
        color: ImportDesign.audioSoft,
        borderRadius: BorderRadius.circular(s(context, 14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: s(context, 16),
            color: ImportDesign.orangeText,
          ),
          SizedBox(width: s(context, 8)),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                isVideo
                    ? '视频仅解析音轨，画面内容不参与分析；原文件不会被修改'
                    : '音频将直接解析音轨；原文件不会被修改',
                style: ImportDesign.ts(
                  context,
                  11,
                  FontWeight.w400,
                  AppColors.muted,
                  lineHeight: ImportDesign.lh11Note,
                ),
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部双按钮（350 宽，gap 12，各 169×48，圆角 16）。
class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.allDone,
    required this.failed,
    required this.onBack,
    required this.onCancel,
    required this.onViewMinutes,
  });

  final bool allDone;
  final bool failed;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onViewMinutes;

  @override
  Widget build(BuildContext context) {
    final String ghostLabel = allDone ? '后台处理' : (failed ? '关闭' : '取消处理');
    final VoidCallback ghostTap = allDone ? onBack : onCancel;
    final String mainLabel = allDone ? '查看纪要' : '后台处理';
    final VoidCallback mainTap = allDone ? onViewMinutes : onBack;
    return Row(
      children: <Widget>[
        Expanded(child: _GhostButton(label: ghostLabel, onTap: ghostTap)),
        SizedBox(width: s(context, 12)),
        Expanded(child: _SolidButton(label: mainLabel, onTap: mainTap)),
      ],
    );
  }
}

/// 白色描边次按钮（48 高，圆角 16，`#F2E4D6` 2px 描边）。
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: s(context, 48),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(s(context, 16)),
            border: Border.all(color: const Color(0xFFF2E4D6), width: s(context, 2)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: ImportDesign.ts(
              context,
              15,
              FontWeight.w600,
              AppColors.muted,
              lineHeight: ImportDesign.lh15,
            ),
          ),
        ),
      ),
    );
  }
}

/// 橙色主按钮（48 高，圆角 16）。
class _SolidButton extends StatelessWidget {
  const _SolidButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: s(context, 48),
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(s(context, 16)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: ImportDesign.ts(
              context,
              15,
              FontWeight.w600,
              Colors.white,
              lineHeight: ImportDesign.lh15,
            ),
          ),
        ),
      ),
    );
  }
}

/// 整体进度：四步等权（每步占 1/4），累计「已完成占比」。
///
/// - 完成的步（`done` / `skip`）记满权重；
/// - 进行中且有百分比的步（① 上传 / ② 分离音轨）按其当前百分比计入；
/// - 其余（等待中 / 进行中但无百分比的 ③④）记 0。
///
/// 旧实现只取进行中单步的百分比（把一步当 100%），或只数已完成步数，
/// 都漏算了另三步；这里把四步合并为一条整体进度。
double _overallPercent(List<ImportStepView> steps) {
  if (steps.isEmpty) return 0.0;
  double completed = 0.0;
  for (final ImportStepView step in steps) {
    if (step.done || step.skip) {
      completed += 1.0;
    } else if (step.running && step.percent != null) {
      completed += step.percent!.clamp(0.0, 1.0);
    }
  }
  return (completed / steps.length).clamp(0.0, 1.0);
}
