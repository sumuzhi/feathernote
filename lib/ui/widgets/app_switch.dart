/// 开关（HTML `#s05 .tgl`）：46×28 胶囊，开启为橙色。
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 设置行开关。
class AppSwitch extends StatelessWidget {
  /// 构造开关。
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  /// 当前值。
  final bool value;

  /// 切换回调。
  final ValueChanged<bool> onChanged;

  /// 无障碍标签。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 46,
          height: 28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: value ? AppColors.orange : const Color(0xFFE4D8CB),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
