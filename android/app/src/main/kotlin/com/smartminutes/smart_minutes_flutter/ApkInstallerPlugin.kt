package com.smartminutes.smart_minutes_flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App 内 APK 安装通道（`com.feathernote.app/apk_installer`）。
 *
 * 取代「跳浏览器手动下载」：Dart 侧下载完 APK 后，通过该通道调起 Android 包安装器。
 * 提供三个方法：
 * - canInstallPackages：Android 8+(API 26) 是否已被授予 REQUEST_INSTALL_PACKAGES；
 * - requestInstallPermission：跳转系统设置页引导用户开启「安装未知应用」；
 * - installApk：用 FileProvider 生成 content:// URI 后 startActivity(ACTION_INSTALL_PACKAGE)。
 *
 * 注意：APK 必须落在 FileProvider 授权目录（files/updates/，见 res/xml/update_file_paths.xml），
 * 直接 file:// 在 Android 7+ 会因 FileUriExposedException 崩溃。
 */
object ApkInstallerPlugin {
    private const val CHANNEL = "com.feathernote.app/apk_installer"
    private const val FILE_PROVIDER_AUTHORITY = "com.feathernote.app.update.fileprovider"

    /** 单 Activity 应用，缓存 activity 引用供 startActivity / packageManager 使用。 */
    private var activity: Activity? = null

    fun register(flutterEngine: FlutterEngine, act: Activity) {
        activity = act
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> result.success(canRequestInstall())
                    "requestInstallPermission" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("NO_PATH", "apk path is null or empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canRequestInstall(): Boolean {
        val act = activity ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            act.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallSettings() {
        val act = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // 直接定位到本应用的「安装未知应用」开关。
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${act.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                act.startActivity(intent)
            } catch (e: ActivityNotFoundException) {
                // 部分 ROM 无此页面 → 退回应用详情页。
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${act.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                act.startActivity(intent)
            }
        }
    }

    private fun installApk(path: String) {
        val act = activity ?: throw IllegalStateException("Activity 不可用")
        val file = File(path)
        if (!file.exists()) throw IllegalStateException("APK 不存在: $path")
        val uri = FileProvider.getUriForFile(act, FILE_PROVIDER_AUTHORITY, file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        act.startActivity(intent)
    }
}
