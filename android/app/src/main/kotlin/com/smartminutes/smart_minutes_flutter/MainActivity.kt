package com.smartminutes.smart_minutes_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 导入音视频平台通道（feathernote/media_import）。
        MediaImportPlugin.register(flutterEngine)
        // App 内 APK 安装通道（com.feathernote.app/apk_installer）。
        ApkInstallerPlugin.register(flutterEngine, this)
    }
}
