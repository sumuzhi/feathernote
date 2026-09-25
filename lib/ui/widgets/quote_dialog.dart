/// 「一句话」详情弹窗：全文展示 + 一键复制到剪贴板。
///
/// 用法：`final copied = await showQuoteDialog(context, quote);`
/// 返回是否发生了复制（调用方据此弹「已复制到剪切板」toast）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 弹出「一句话」详情；返回是否执行了复制。
Future<bool> showQuoteDialog(BuildContext context, String quote) async {
  final bool? copied = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _QuoteDialog(quote: quote),
  );
  return copied ?? false;
}

class _QuoteDialog extends StatefulWidget {
  const _QuoteDialog({required this.quote});

  final String quote;

  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  bool _copied = false;

  /// 把「句子 —— 出处」拆为句子与出处（无出处则整体为句子）。
  (String, String?) get _parsed {
    final int sep = widget.quote.lastIndexOf(' —— ');
    if (sep <= 0) return (widget.quote, null);
    return (widget.quote.substring(0, sep), widget.quote.substring(sep + 4));
  }

  Future<void> _copy() async {
    final (String sentence, String? _) = _parsed;
    await Clipboard.setData(ClipboardData(text: sentence));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final (String sentence, String? source) = _parsed;
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('一句话', style: AppTextStyles.subHead),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sentence,
            style: AppTextStyles.cardTitle.copyWith(height: 1.6),
          ),
          if (source != null) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '—— $source',
                style: AppTextStyles.meta.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('关闭', style: AppTextStyles.settingTitle.copyWith(color: AppColors.muted)),
        ),
        TextButton.icon(
          onPressed: _copied ? null : _copy,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 16,
            color: AppColors.orange,
          ),
          label: Text(
            _copied ? '已复制' : '复制',
            style: AppTextStyles.settingTitle.copyWith(color: AppColors.orange),
          ),
        ),
      ],
    );
  }
}
