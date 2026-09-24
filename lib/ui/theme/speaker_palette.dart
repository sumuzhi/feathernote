/// 说话人色板（8 组，前景 + 浅底）。
///
/// 对齐 HTML `:root` 的 `--sp1`…`--sp8` 与 `--sp1-bg`…`--sp8-bg`。
/// 旧规格只有 3 组，是错的；说话人过多（s13）需要用到第 8 组灰色。
library;

import 'package:flutter/material.dart';

/// 说话人配色。
class SpeakerPalette {
  const SpeakerPalette({required this.foreground, required this.background});

  /// 前景色（头像底 / 说话人名 / 圆点）。
  final Color foreground;

  /// 浅底色（chip 底 / 命中高亮）。
  final Color background;
}

/// 8 组说话人配色（下标 0 → 说话人 1）。
const List<SpeakerPalette> kSpeakerPalette = <SpeakerPalette>[
  SpeakerPalette(foreground: Color(0xFFF0783C), background: Color(0xFFFDEEE2)),
  SpeakerPalette(foreground: Color(0xFF4E9A6A), background: Color(0xFFE9F3ED)),
  SpeakerPalette(foreground: Color(0xFF7C6BB0), background: Color(0xFFEFEBF7)),
  SpeakerPalette(foreground: Color(0xFF3E7CB8), background: Color(0xFFE7F0F8)),
  SpeakerPalette(foreground: Color(0xFFC75B8A), background: Color(0xFFF9EAF1)),
  SpeakerPalette(foreground: Color(0xFFB08D3E), background: Color(0xFFF6EFDE)),
  SpeakerPalette(foreground: Color(0xFF3E9B94), background: Color(0xFFE4F2F1)),
  SpeakerPalette(foreground: Color(0xFFA79A8E), background: Color(0xFFF0EAE4)),
];

/// 取第 [index] 组配色（越界时循环取模，保证 8 人以上不崩）。
SpeakerPalette speakerPaletteAt(int index) {
  if (index < 0) return kSpeakerPalette[0];
  return kSpeakerPalette[index % kSpeakerPalette.length];
}

/// 说话人前景色（1-based 序号）。
Color speakerColor(int ordinal1Based) => speakerPaletteAt(ordinal1Based - 1).foreground;

/// 说话人浅底色（1-based 序号）。
Color speakerSoftColor(int ordinal1Based) => speakerPaletteAt(ordinal1Based - 1).background;
