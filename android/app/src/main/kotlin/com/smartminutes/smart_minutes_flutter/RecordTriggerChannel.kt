package com.smartminutes.smart_minutes_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 按键触发通道（`feathernote/record_trigger`）。
 *
 * 桥接两端：
 * - **原生 → Dart**：`RecordTriggerService` 收到命令后，通过 [deliver] 把
 *   `toggle`/`start`/`stop` 投给 Dart 侧（`RecordTriggerController` 消费）；
 * - **Dart → 原生**：同步录音状态（供 root 守护进程决定震动语义）、查权限、通知 UI 附着。
 *
 * **命令不丢失设计**：`am start` 可能在 Dart 侧尚未就绪时到达（冷启动，引擎刚创建）。
 * 因此命令先落盘到 `files/pending_trigger`，Dart 侧启动后主动 `consumePending` 补取。
 */
object RecordTriggerChannel {

    /** 通道名（与 Dart 侧 `record_trigger_channel.dart` 严格一致）。 */
    private const val CHANNEL = "feathernote/record_trigger"

    /** 待处理命令落盘文件名（app 私有 files 目录）。 */
    private const val PENDING_FILE = "pending_trigger"

    /** 状态文件名（root 守护进程读取；路径须与 keytriggerd.c 的 STATE_PATH 一致）。 */
    private const val STATE_FILE = "trigger_state"

    private var channel: MethodChannel? = null

    /** 内存中的待处理命令（比落盘快；进程刚起时靠落盘兜底）。 */
    @Volatile
    private var pendingCommand: String? = null

    /** 注册通道（幂等；重复注册会替换 handler，避免多引擎串台）。 */
    fun register(engine: FlutterEngine, context: Context) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> result.success(consumePending(context))
                "syncState" -> {
                    val state = call.argument<String>("state") ?: "idle"
                    syncState(context, state)
                    result.success(true)
                }
                "hasRecordPermission" -> {
                    // headless 下 record 插件的 hasPermission() 恒返回 false
                    //（插件在 activity == null 时直接 short-circuit），这里直查。
                    val granted = ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "uiAttached" -> {
                    // Dart 侧确认 UI 已挂上（无需原生动作）。
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    /**
     * 通知 Dart 侧「UI 已附着」，需要补挂 `runApp`。
     *
     * 场景：进程因按键触发而 headless 启动（没跑 `runApp`），随后用户打开 app。
     * 此时引擎已在跑 Dart，`main()` 不会再次执行，必须由原生侧主动触发补挂。
     */
    fun notifyUiAttached(engine: FlutterEngine) {
        channel?.invokeMethod("onUiAttached", null)
    }

    /**
     * 投递命令给 Dart 侧（由 [RecordTriggerService] 调用）。
     *
     * 若引擎尚未跑起 Dart 入口，命令落盘并等待 Dart 侧启动后主动拉取。
     */
    fun deliver(engine: FlutterEngine, context: Context, command: String) {
        pendingCommand = command
        writePendingFile(context, command)

        val ch = channel ?: return
        ch.invokeMethod("onTrigger", mapOf("command" to command), object : MethodChannel.Result {
            override fun success(result: Any?) {
                clearPending(context)
            }

            override fun error(code: String, message: String?, details: Any?) {
                // 保留落盘，等 Dart 侧 consumePending。
            }

            override fun notImplemented() {
                // 同上。
            }
        })
    }

    /** Dart 侧启动后拉取一次未消费的命令（冷启动补投）。 */
    private fun consumePending(context: Context): String? {
        val cmd = pendingCommand ?: readPendingFile(context)
        pendingCommand = null
        clearPending(context)
        return cmd
    }

    /**
     * 同步录音状态到文件，供 root 守护进程判断震动语义。
     *
     * 路径：`/data/user/0/com.feathernote.app/files/trigger_state`
     * （须与 `keytriggerd.c` 的 `STATE_PATH` 一致）。
     */
    private fun syncState(context: Context, state: String) {
        val normalized = if (state == "recording") "recording" else "idle"
        try {
            File(context.filesDir, STATE_FILE).writeText(normalized)
        } catch (_: Throwable) {
            // 写失败不影响录音主流程（只是震动语义退化）。
        }
    }

    // ── 落盘辅助 ──────────────────────────────────────────────────────────

    private fun pendingFile(context: Context): File = File(context.filesDir, PENDING_FILE)

    private fun writePendingFile(context: Context, command: String) {
        try {
            pendingFile(context).writeText(command)
        } catch (_: Throwable) {
            // 落盘失败仍尝试直接投递（尽力而为）。
        }
    }

    private fun readPendingFile(context: Context): String? = try {
        val f = pendingFile(context)
        if (f.exists()) f.readText().trim().ifEmpty { null } else null
    } catch (_: Throwable) {
        null
    }

    private fun clearPending(context: Context) {
        try {
            pendingFile(context).delete()
        } catch (_: Throwable) {
            // ignore
        }
    }
}
