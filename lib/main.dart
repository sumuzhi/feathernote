/// 应用入口。
///
/// 方案 B：**没有独立进程的 Node 服务**，后端（引擎 / 存储 / 服务）全部
/// 在 Dart 进程内装配，UI 通过 `BackendApi` 门面调用。详见 `docs/ARCHITECTURE.md`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  runApp(const ProviderScope(child: SmartMinutesApp()));
}
