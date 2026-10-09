/// 屏 14：上传 · 选择文件（HTML 设计稿屏 14，画布 390×844）。
///
/// 逐元素对照 `14 · 上传 · 选择文件/index.html`：
/// 顶栏（返回箭头 / 「导入音视频」/「帮助」）→ 说明文案 → 拖拽区（上传图标 /
/// 「拖拽文件到此处」/ 格式与体积说明 /「选择文件」按钮）→ 音频 + 视频格式卡
/// （视频卡带「自动分离音轨」角标）→ 限制说明条 →「最近导入」+ 最近卡片。
///
/// 视觉层只做渲染：数据与交互全部由 `lib/ui/pages/import_page.dart` 翻译。
/// 顶部状态栏（9:41 / 信号 / 电量）是画布产物，不还原（见 `screen_frame.dart`）。
/// 底部 TabBar 同样不渲染（产品指令：导入两屏都不再显示 Tab 栏），内容区按
/// 782（= 844 − 62）撑满；`onTabTap` / `selectedTab` 仅为保持调用方契约。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/import_design.dart';
import '../utils/design_scale.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/history_card.dart';
import 'screen_frame.dart';

/// 屏 14 视觉。
class ImportIdleScreen extends StatelessWidget {
  /// 构造屏 14。
  const ImportIdleScreen({
    super.key,
    required this.onPickFile,
    required this.recentItems,
    required this.onBack,
    this.onTabTap,
    this.onHelp,
    this.selectedTab = 0,
    this.picking = false,
  });

  /// 点击「选择文件」（整块拖拽区也可点，移动端没有拖拽）。
  final VoidCallback onPickFile;

  /// 最近导入（最多 5 条）。
  final List<HistoryItemView> recentItems;

  /// 底部 Tab 点击（本屏不渲染 TabBar，保留入参以兼容调用方）。
  final ValueChanged<int>? onTabTap;

  /// 顶栏返回。
  final VoidCallback onBack;

  /// 顶栏「帮助」；为 null 时按设计稿只作静态文案（HTML 未定义跳转）。
  final VoidCallback? onHelp;

  /// 选中 Tab（本屏不渲染 TabBar，保留入参以兼容调用方）。
  final int selectedTab;

  /// 是否在选择文件中（按钮禁用）。
  final bool picking;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      // 不传 tabIndex / onTabTap → 不渲染底部 TabBar（同屏 15）：
      // 内容区按设计稿 782（= 844 − 62）撑满整屏，底部只留 24 的内容内边距
      // （+ 系统 home indicator 安全区），不再给 TabBar 预留 95。
      bottomSpacer: s(context, 24) + MediaQuery.viewPaddingOf(context).bottom,
      // 固定头部：顶栏（用户要求：与完整转写页统一，返回 icon 带背景圆形底）
      // + 其上 4、其下 12 的间距一起挪出滚动区。
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: s(context, 4)),
          // 用户要求：title 居中、删掉右侧「帮助」icon。
          AppTopBar(
            title: '导入音视频',
            subtitle: '',
            leadingIcon: Icons.chevron_left_rounded,
            onLeading: onBack,
          ),
          SizedBox(height: s(context, 12)),
        ],
      ),
      body: Padding(
        // HTML 内容区 padding: 4px 20px 0（顶部 4 已随 header 一起给到顶栏）。
        padding: EdgeInsets.symmetric(horizontal: s(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Intro(),
            SizedBox(height: s(context, 12)),
            _DropZone(onPickFile: onPickFile, picking: picking),
            SizedBox(height: s(context, 12)),
            _FormatRow(),
            SizedBox(height: s(context, 12)),
            _LimitNote(),
            if (recentItems.isNotEmpty) ...<Widget>[
              SizedBox(height: s(context, 12)),
              _RecentHeader(),
              for (final HistoryItemView item in recentItems) ...<Widget>[
                SizedBox(height: s(context, 12)),
                _RecentCard(item: item),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 说明文案（12 / w400 / #8B7565，line-height 19.2，设计稿单行）。
///
/// 用 [FittedBox] 而非换行：设计稿是一行，系统字体比设计字体略宽时轻微缩小
/// 让文案保持一行（文字本身一字不改）。
class _Intro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        '支持音频与视频文件导入，视频会自动分离音轨后再转写与总结',
        style: ImportDesign.ts(
          context,
          12,
          FontWeight.w400,
          AppColors.muted,
          lineHeight: ImportDesign.lh12,
        ),
        maxLines: 1,
      ),
    );
  }
}

/// 拖拽区（350×180，圆角 24，白底 + `#F2C9A3` 3px 描边 + 暖棕阴影）。
///
/// 移动端没有拖拽，整块卡片与「选择文件」按钮都走 [onPickFile]。
class _DropZone extends StatelessWidget {
  const _DropZone({required this.onPickFile, required this.picking});

  final VoidCallback onPickFile;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '选择音视频文件',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: picking ? null : onPickFile,
        child: Container(
          width: double.infinity,
          // 设计稿 180 高（内容 148 + 内边距 32）；用 minHeight 而不是固定高，
          // 字体度量略有出入时卡片长高 1~2px 而不是抛溢出条。
          constraints: BoxConstraints(minHeight: s(context, 180)),
          // HTML 的描边是「画在 padding 带内」的（不占布局），Flutter 的 border
          // 会占布局，因此把 padding 各减掉 3，内容盒仍是 314×148。
          padding: EdgeInsets.symmetric(
            horizontal: s(context, 18 - 3),
            vertical: s(context, 16 - 3),
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(s(context, 24)),
            border: Border.all(
              color: ImportDesign.zoneBorder,
              width: s(context, 3),
            ),
            boxShadow: ImportDesign.zoneShadow(context),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // 上传图标：52×52 圆底 #FFF0E3 + 向上箭头（含底线）。
              Container(
                width: s(context, 52),
                height: s(context, 52),
                decoration: const BoxDecoration(
                  color: ImportDesign.audioSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.upload_rounded,
                  size: s(context, 28),
                  color: AppColors.orange,
                ),
              ),
              SizedBox(height: s(context, 6)),
              Text(
                '拖拽文件到此处',
                style: ImportDesign.ts(
                  context,
                  15,
                  FontWeight.w600,
                  AppColors.ink,
                  lineHeight: ImportDesign.lh15,
                ),
              ),
              SizedBox(height: s(context, 6)),
              Text(
                'MP4 / MOV / MP3 / WAV · 单个文件 ≤ 2GB',
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
              SizedBox(height: s(context, 6)),
              _PickButton(onTap: picking ? null : onPickFile, picking: picking),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「选择文件」按钮（118×40，圆角 14，`#F0783C` 实心 + 文件夹图标）。
class _PickButton extends StatelessWidget {
  const _PickButton({required this.onTap, required this.picking});

  final VoidCallback? onTap;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '选择文件',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: s(context, 40),
          padding: EdgeInsets.symmetric(horizontal: s(context, 20)),
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(s(context, 14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.folder_rounded,
                size: s(context, 16),
                color: Colors.white,
              ),
              SizedBox(width: s(context, 6)),
              Text(
                picking ? '正在打开文件选择器…' : '选择文件',
                style: ImportDesign.ts(
                  context,
                  14,
                  FontWeight.w600,
                  Colors.white,
                  lineHeight: ImportDesign.lh14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 格式说明双卡（音频 / 视频，等宽 169，圆角 18，白底 + 暖棕阴影）。
class _FormatRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Expanded(
          child: _FormatCard(
            tileColor: ImportDesign.audioSoft,
            iconColor: ImportDesign.orangeText,
            icon: Icons.bar_chart_rounded,
            name: '音频文件',
            lines: <String>['MP3 / WAV / M4A / AAC', 'FLAC / OGG / AMR'],
          ),
        ),
        SizedBox(width: s(context, 12)),
        const Expanded(
          child: _FormatCard(
            tileColor: ImportDesign.videoSoft,
            iconColor: ImportDesign.videoInk,
            icon: Icons.video_file_rounded,
            name: '视频文件',
            lines: <String>['MP4 / MOV / MKV / AVI', 'WebM / FLV / TS'],
            chip: true,
          ),
        ),
      ],
    );
  }
}

/// 单张格式卡（padding 14，gap 7）。
class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.tileColor,
    required this.iconColor,
    required this.icon,
    required this.name,
    required this.lines,
    this.chip = false,
  });

  final Color tileColor;
  final Color iconColor;
  final IconData icon;
  final String name;
  final List<String> lines;
  final bool chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(s(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(s(context, 18)),
        boxShadow: ImportDesign.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: s(context, 32),
            height: s(context, 32),
            decoration: BoxDecoration(color: tileColor, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: s(context, 18), color: iconColor),
          ),
          SizedBox(height: s(context, 7)),
          Text(
            name,
            style: ImportDesign.ts(context, 13, FontWeight.w600, AppColors.ink),
          ),
          SizedBox(height: s(context, 7)),
          for (final String line in lines)
            Text(
              line,
              style: ImportDesign.ts(
                context,
                11,
                FontWeight.w400,
                AppColors.muted,
                lineHeight: ImportDesign.lh11Lines,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (chip) ...<Widget>[
            SizedBox(height: s(context, 7)),
            _TrackChip(),
          ],
        ],
      ),
    );
  }
}

/// 「自动分离音轨」角标（89×20，圆角 8，`#FFF0E3` 底 + `#C2591F` 字）。
class _TrackChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: s(context, 7),
        vertical: s(context, 3),
      ),
      decoration: BoxDecoration(
        color: ImportDesign.audioSoft,
        borderRadius: BorderRadius.circular(s(context, 8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.upload_rounded,
            size: s(context, 11),
            color: ImportDesign.orangeText,
          ),
          SizedBox(width: s(context, 4)),
          Text(
            '自动分离音轨',
            style: ImportDesign.ts(
              context,
              10,
              FontWeight.w500,
              ImportDesign.orangeText,
              lineHeight: ImportDesign.lh10,
            ),
          ),
        ],
      ),
    );
  }
}

/// 限制说明条（350 宽，圆角 14，`#FFF0E3` 底，信息图标 + 两行灰字）。
class _LimitNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: s(context, 14),
        vertical: s(context, 10),
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
            child: Text(
              '单个文件 ≤ 2GB · 时长 ≤ 4 小时；视频仅解析音轨，画面内容不参与分析',
              style: ImportDesign.ts(
                context,
                11,
                FontWeight.w400,
                AppColors.muted,
                lineHeight: ImportDesign.lh11Note,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「最近导入」标题（13 / w600 / #3A2A20）。
class _RecentHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      '最近导入',
      style: ImportDesign.ts(context, 13, FontWeight.w600, AppColors.ink),
    );
  }
}

/// 最近导入卡片（350×60，圆角 14，白底 + 暖棕阴影）。
///
/// 图标底色按文件名后缀判断：视频 = 浅紫 + 视频图标，音频 = 浅橙 + 音频图标
/// （HTML 里两条示例分别是 .mp4 与 .m4a，本项目视图层没有 kind 字段）。
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item});

  final HistoryItemView item;

  @override
  Widget build(BuildContext context) {
    final bool video = _isVideoName(item.title);
    return Semantics(
      button: item.onTap != null,
      label: item.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: Container(
          width: double.infinity,
          // 设计稿 60 高（内容 38 + 内边距 22）。
          constraints: BoxConstraints(minHeight: s(context, 60)),
          padding: EdgeInsets.symmetric(
            horizontal: s(context, 12),
            vertical: s(context, 11),
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(s(context, 14)),
            boxShadow: ImportDesign.cardShadow(context),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: s(context, 32),
                height: s(context, 32),
                decoration: BoxDecoration(
                  color: video ? ImportDesign.videoSoft : ImportDesign.audioSoft,
                  borderRadius: BorderRadius.circular(s(context, 10)),
                ),
                alignment: Alignment.center,
                child: Icon(
                  video ? Icons.video_file_rounded : Icons.audio_file_rounded,
                  size: s(context, 18),
                  color: video ? ImportDesign.videoInk : ImportDesign.orangeText,
                ),
              ),
              SizedBox(width: s(context, 10)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: ImportDesign.ts(context, 13, FontWeight.w600, AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: s(context, 3)),
                    Text(
                      item.meta,
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
              SizedBox(width: s(context, 10)),
              Icon(
                Icons.chevron_right_rounded,
                size: s(context, 14),
                color: ImportDesign.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 文件名是否视频（决定最近卡图标配色）。
bool _isVideoName(String title) {
  final String lower = title.toLowerCase();
  const List<String> videoExt = <String>[
    '.mp4', '.mov', '.m4v', '.mkv', '.avi', '.webm', '.flv', '.ts', '.3gp',
  ];
  for (final String ext in videoExt) {
    if (lower.endsWith(ext)) return true;
  }
  return false;
}
