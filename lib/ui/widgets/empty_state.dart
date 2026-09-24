/// 空态（HTML `.empty-hero`）：圆环图标 + 标题 + 说明 + 操作。
///
/// 两种底：橙色浅底（`#s08` 无记录）与灰底（`#s10` 搜索无结果）。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空态。
class AppEmptyState extends StatelessWidget {
  /// 构造空态。
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.gray = false,
    this.titleSize = 20,
    this.topPadding = 64,
    this.cta,
    this.actions,
  });

  /// 圆环内的图标。
  final IconData icon;

  /// 标题。
  final String title;

  /// 说明文案。
  final String description;

  /// 是否使用灰环（搜索无结果）。
  final bool gray;

  /// 标题字号（s10 为 18）。
  final double titleSize;

  /// 顶部留白（s08 = 64，s10 = 96）。
  final double topPadding;

  /// 主 CTA（s08 的「开始第一次录音」）。
  final Widget? cta;

  /// 两个并排操作（s10 的「清空筛选条件 / 搜索全部时间」）。
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(40, topPadding, 40, 0),
      child: Column(
        children: <Widget>[
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: gray ? AppColors.grayWash : AppColors.orangeSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: gray ? 40 : 42,
              color: gray ? const Color(0xFFA79A8E) : AppColors.orange,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.sectionTitle.copyWith(fontSize: titleSize),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTextStyles.meta.copyWith(height: 1.6),
          ),
          if (cta != null) ...<Widget>[
            const SizedBox(height: 22),
            cta!,
          ],
          if (actions != null && actions!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < actions!.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 12),
                  actions![i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
