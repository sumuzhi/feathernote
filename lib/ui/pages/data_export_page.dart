/// 数据导出页（设置「数据库」行点入）。
///
/// 取代原「设置页一键全量导出」：进入本页列出**全部**会议数据，支持
/// - 勾选（checkbox + 全选）做**批量导出**；
/// - 每条右侧「导出」图标做**单条导出**；
/// - 底部「导出全部」做**全量导出**；
/// 三种模式统一复用 [exportBackup]（后台 isolate 打包，UI 不阻塞 + 进度 + 取消
/// + 前台服务保活）。导出位置沿用设置页持久化的值，本页可就地切换。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/recording_foreground_service.dart';
import '../../domain/meeting.dart';
import '../providers/app_providers.dart';
import '../screens/screen_frame.dart';
import '../theme/app_theme.dart';
import '../utils/backup_exporter.dart';
import '../utils/export_destination.dart';
import '../utils/exporter.dart' show ExportCancelledException;
import '../utils/formatters.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/export_destination_sheet.dart';

/// 数据导出页。
class DataExportPage extends ConsumerStatefulWidget {
  /// 构造数据导出页。
  const DataExportPage({super.key});

  @override
  ConsumerState<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends ConsumerState<DataExportPage> {
  /// 已勾选的会议 ID。
  final Set<String> _selected = <String>{};

  /// 导出位置（同设置页持久化，本页可就地切换）。
  ExportDestination _destination = ExportDestination.appDownload;

  /// 是否处于「选择模式」（用户要求：默认不带复选框，点「选择」后才出现
  /// 复选框与底部导出条）。
  bool _selecting = false;

  /// 是否正在导出（禁用勾选 / 并发）。
  bool _exporting = false;

  /// 正在单条导出的会议 ID（行内图标转 loading 用；批量导出为 null）。
  String? _exportingId;

  /// 导出进度（0–1）。
  double _progress = 0;

  /// 导出阶段文案。
  String _phase = '';

  /// 取消令牌。
  BackupCancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _loadDestination();
  }

  /// 读取持久化导出位置。
  Future<void> _loadDestination() async {
    final ExportDestination saved = await loadExportDestination();
    if (!mounted) return;
    setState(() => _destination = saved);
  }

  /// 切换单条勾选。
  void _toggle(String id) {
    if (_exporting) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  /// 进入 / 退出选择模式（顶栏「选择」按钮）。
  ///
  /// 退出时清空已选；导出中与空列表不允许进入。
  void _toggleSelecting(List<MeetingSummary> all) {
    if (_exporting || all.isEmpty) return;
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _selected.clear();
    });
  }

  /// 全选 / 取消全选。
  void _toggleAll(List<MeetingSummary> all) {
    if (_exporting || all.isEmpty) return;
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((MeetingSummary m) => m.id));
      }
    });
  }

  /// 切换导出位置。
  Future<void> _pickDestination() async {
    final ExportDestination? picked = await showExportDestinationSheet(context);
    if (picked == null || !mounted) return;
    await saveExportDestination(picked);
    if (!mounted) return;
    setState(() => _destination = picked);
  }

  /// 执行导出（单条 / 批量 / 全部统一入口：传入要导出的 [summaries]）。
  ///
  /// 重活在后台 isolate（[exportBackup]），UI 不阻塞；借前台服务保活不被系统回收；
  /// 带进度 + 取消。失败 / 取消均有可读 toast。
  Future<void> _runExport(List<MeetingSummary> summaries) async {
    if (_exporting || summaries.isEmpty) return;
    setState(() {
      _exporting = true;
      // 单条导出：行内图标转 loading（用户要求）；批量导出无单行归属。
      _exportingId = summaries.length == 1 ? summaries.first.id : null;
      _progress = 0;
      _phase = '准备导出';
    });
    final BackupCancelToken token = BackupCancelToken();
    _cancel = token;
    await RecordingForegroundService.instance.acquire(
      'export',
      notificationText: '正在导出数据备份，点击回到应用',
    );
    try {
      final api = await ref.read(backendProvider.future);
      final int? schemaVersion =
          (await ref.read(healthProvider.future)).schemaVersion;
      // 列表项仅 [MeetingSummary]，导出需要全量 [Meeting]，逐条拉取。
      final List<Meeting> meetings = <Meeting>[];
      for (final MeetingSummary s in summaries) {
        final Meeting? m = await api.getMeeting(s.id);
        if (m != null) meetings.add(m);
      }
      if (meetings.isEmpty) {
        if (!mounted) return;
        ref
            .read(toastProvider.notifier)
            .show('没有可导出的数据', tone: ToastTone.warning);
        return;
      }
      final ({String location, BackupCancelToken handle}) result =
          await exportBackup(
        meetings: meetings,
        destination: _destination,
        schemaVersion: schemaVersion,
        audioPathResolver: (Meeting m) => api.getAudioPath(m.id),
        cancelToken: token,
        onProgress: (double fraction, String phase) {
          if (!mounted) return;
          setState(() {
            _progress = fraction;
            _phase = phase;
          });
        },
      );
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('已导出到 ${result.location}', tone: ToastTone.success);
    } on ExportCancelledException {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('已取消导出', tone: ToastTone.info);
      return;
    } catch (error) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('导出失败：$error', tone: ToastTone.warning);
    } finally {
      await RecordingForegroundService.instance.release('export');
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportingId = null;
          _progress = 0;
          _phase = '';
          _cancel = null;
          // 导出完成 / 取消 / 失败后退出选择模式（用户要求的选择流闭环）。
          _selecting = false;
          _selected.clear();
        });
      }
    }
  }

  /// 底部「导出选中」。
  void _exportSelected(List<MeetingSummary> all) {
    final List<MeetingSummary> chosen =
        all.where((MeetingSummary m) => _selected.contains(m.id)).toList();
    if (chosen.isEmpty) {
      _toast('请先勾选要导出的会议');
      return;
    }
    _runExport(chosen);
  }

  /// 单条导出（列表项右侧图标）。
  void _exportSingle(MeetingSummary item) => _runExport(<MeetingSummary>[item]);

  void _toast(String text) =>
      ref.read(toastProvider.notifier).show(text, tone: ToastTone.info);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MeetingSummary>> asyncMeetings =
        ref.watch(meetingsProvider);
    final List<MeetingSummary> all =
        asyncMeetings.value ?? const <MeetingSummary>[];
    final DateTime now = DateTime.now();
    final bool allSelected = _selecting &&
        all.isNotEmpty &&
        _selected.length == all.length;

    return ScreenFrame(
      scrollable: true,
      bottomSpacer: _bottomSpacer(context),
      header: _buildHeader(all, allSelected),
      bottomCta: _buildActionBar(all),
      body: _buildBody(all, now),
    );
  }

  /// 内容底部留白：选择模式 / 导出中有悬浮操作条（按钮高 56 + 上下 padding 28 +
  /// [AppSpacing.ctaBottom] + 系统底边距），必须留够否则最后一条被遮；
  /// 默认模式无操作条，只留常规间距。
  double _bottomSpacer(BuildContext context) {
    if (_selecting || _exporting) {
      return 120 + MediaQuery.viewPaddingOf(context).bottom;
    }
    return 32 + MediaQuery.viewPaddingOf(context).bottom;
  }

  /// 固定头部：顶栏（返回 + 计数 + 「选择」动作）+ 控制行。
  Widget _buildHeader(List<MeetingSummary> all, bool allSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        AppTopBar(
          title: '数据导出',
          subtitle: _selecting
              ? '已选 ${_selected.length} / ${all.length} 条'
              : (all.isEmpty ? '暂无数据' : '共 ${all.length} 条'),
          leadingIcon: Icons.chevron_left_rounded,
          onLeading: () => context.pop(),
          actionIcon: _selecting ? Icons.close_rounded : Icons.checklist_rounded,
          onAction: () => _toggleSelecting(all),
          actionTooltip: _selecting ? '退出选择' : '选择',
        ),
        const SizedBox(height: 8),
        _buildControlRow(all, allSelected),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 控制行：选择模式下显示「全选」（左）+ 导出位置 chip 常驻（右，可切换）。
  Widget _buildControlRow(List<MeetingSummary> all, bool allSelected) {
    final String destLabel = exportDestinationLabel(_destination);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: <Widget>[
          if (_selecting) ...<Widget>[
            GestureDetector(
              onTap: () => _toggleAll(all),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _CheckBox(
                    value: allSelected,
                    onChanged: (_) => _toggleAll(all),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    allSelected ? '取消全选' : '全选',
                    style: AppTextStyles.body15,
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: _pickDestination,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.orangeWash,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 14,
                    color: AppColors.orange,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      destLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.metaSmall
                          .copyWith(color: AppColors.orange),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.unfold_more_rounded,
                    size: 14,
                    color: AppColors.orange,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表主体。
  Widget _buildBody(List<MeetingSummary> all, DateTime now) {
    if (all.isEmpty) {
      return _buildEmpty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < all.length; i++)
          _ExportRow(
            item: all[i],
            now: now,
            selecting: _selecting,
            selected: _selected.contains(all[i].id),
            exporting: _exporting,
            loading: _exportingId == all[i].id,
            onToggle: () => _toggle(all[i].id),
            onExport: () => _exportSingle(all[i]),
          ),
      ],
    );
  }

  /// 空态。
  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.orangeSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.inbox_rounded,
              size: 32,
              color: AppColors.orange,
            ),
          ),
          const SizedBox(height: 18),
          Text('还没有会议数据', style: AppTextStyles.cardHead),
          const SizedBox(height: 6),
          Text(
            '录音并生成纪要后，数据会出现在这里',
            style: AppTextStyles.meta,
          ),
        ],
      ),
    );
  }

  /// 底部操作条：导出中显示进度 + 取消；选择模式显示「导出选中 / 导出全部」；
  /// 默认模式无操作条（用户要求：点「选择」后才出现下方的导出）。
  Widget? _buildActionBar(List<MeetingSummary> all) {
    if (_exporting) {
      return _ExportProgressCard(
        progress: _progress,
        phase: _phase,
        onCancel: () => _cancel?.cancel(),
      );
    }
    if (!_selecting) return null;
    final int count = _selected.length;
    // 用户要求：底部只保留「导出选中」一个操作（导出全部 = 全选 + 导出选中）。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
      child: Opacity(
        opacity: count == 0 ? 0.5 : 1,
        child: _ActionButton(
          label: count == 0 ? '导出选中' : '导出选中 ($count)',
          onTap: count == 0 ? null : () => _exportSelected(all),
        ),
      ),
    );
  }
}

/// 列表项：checkbox（仅选择模式）+ 标题 + 元信息 + 单条导出图标。
class _ExportRow extends StatelessWidget {
  /// 构造列表项。
  const _ExportRow({
    required this.item,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.exporting,
    required this.loading,
    required this.onToggle,
    required this.onExport,
  });

  /// 会议摘要。
  final MeetingSummary item;

  /// 当前时刻（用于相对日期）。
  final DateTime now;

  /// 是否处于选择模式（显示复选框、整行可点勾选）。
  final bool selecting;

  /// 是否被勾选。
  final bool selected;

  /// 是否正在导出（禁用单条按钮）。
  final bool exporting;

  /// 本行是否正在单条导出（下载图标转 loading）。
  final bool loading;

  /// 勾选切换。
  final VoidCallback onToggle;

  /// 单条导出。
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final String meta =
        '${formatDurationCn(item.durationMs)} · ${formatDayTime(item.createdAt, now: now)} · ${formatPeople(item.speakerCount)}';
    return GestureDetector(
      // 仅选择模式下整行点击勾选；默认模式行点击无动作（单条导出走右侧图标）。
      onTap: selecting ? onToggle : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 水平边距对齐 [AppSpacing.page]：此前铺满屏宽，选中边框顶到屏幕
        // 两侧，观感像「边框占据整个屏幕」（用户反馈）。
        margin: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 0),
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        // 选中态只变**背景色**（用户要求：点击时 item 不发生位移）——
        // 此前用 Border.all 指示选中，边框参与装饰绘制导致卡片视觉下沉/位移。
        decoration: BoxDecoration(
          color: selecting && selected ? AppColors.orangeSoft : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card2),
          boxShadow: AppShadow.card,
        ),
        child: Row(
          children: <Widget>[
            if (selecting) ...<Widget>[
              _CheckBox(value: selected, onChanged: (_) => onToggle()),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title.isEmpty ? '未命名会议' : item.title,
                    style: AppTextStyles.itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    meta,
                    style: AppTextStyles.metaSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: '导出该条',
              child: GestureDetector(
                onTap: exporting ? null : onExport,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  // 单条导出中：图标转 loading（用户要求）。
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.orange,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.download_rounded,
                          size: 19,
                          color:
                              exporting ? AppColors.faint : AppColors.orange,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义圆角 checkbox（对齐设计 token：橙底白勾 / 浅棕描边）。
class _CheckBox extends StatelessWidget {
  /// 构造 checkbox。
  const _CheckBox({required this.value, required this.onChanged});

  /// 是否选中。
  final bool value;

  /// 切换。
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value ? AppColors.orange : AppColors.card,
          borderRadius: BorderRadius.circular(7),
          border: value ? null : Border.all(color: AppColors.faint, width: 1.5),
        ),
        alignment: Alignment.center,
        child: value
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 操作条按钮（橙底 / 白底胶囊，复用 App 按钮族视觉）。
class _ActionButton extends StatelessWidget {
  /// 构造按钮。
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.ghost = false,
  });

  /// 文案。
  final String label;

  /// 点击（null = 禁用）。
  final VoidCallback? onTap;

  /// 是否为白底次按钮。
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: ghost ? AppColors.card : AppColors.orange,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: ghost ? AppShadow.card : AppShadow.orangeButton,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: ghost
                ? AppTextStyles.buttonSecondary
                : AppTextStyles.button.copyWith(
                    color: enabled ? Colors.white : AppColors.disabled,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 导出中进度卡（顶部阶段文案 + 进度条 + 百分比 + 取消）。
class _ExportProgressCard extends StatelessWidget {
  /// 构造进度卡。
  const _ExportProgressCard({
    required this.progress,
    required this.phase,
    required this.onCancel,
  });

  /// 进度（0–1）。
  final double progress;

  /// 阶段文案。
  final String phase;

  /// 取消。
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  phase.isNotEmpty ? phase : '正在导出…',
                  style: AppTextStyles.metaSmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 6,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.line,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.orange,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(progress * 100).round()}%',
            style: AppTextStyles.metaSmall,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onCancel,
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
