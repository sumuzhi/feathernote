/// 应用入口。
///
/// 方案 B：**没有独立进程的 Node 服务**，后端（引擎 / 存储 / 服务）全部
/// 在 Dart 进程内装配，UI 通过 `BackendApi` 门面调用。详见 `docs/ARCHITECTURE.md`。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_store_plus/media_store_plus.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 导出位置初始化：默认写公共 Download/SmartMinutes/（MediaStore，10+ 零权限）。
  // 失败不阻塞启动（导出时有兜底回落应用文档目录）。
  if (Platform.isAndroid) {
    try {
      await MediaStore.ensureInitialized();
      MediaStore.appFolder = 'SmartMinutes';
    } catch (_) {
      // ignore: 初始化失败时导出回落应用内目录。
    }
  }
  runApp(const ProviderScope(child: SmartMinutesApp()));
}
