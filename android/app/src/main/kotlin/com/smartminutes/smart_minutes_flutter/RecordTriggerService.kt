package com.smartminutes.smart_minutes_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 按键触发的**前台服务**：把 `start`/`stop`/`toggle` 命令交给 Flutter 侧执行。
 *
 * ## 为什么必须走前台服务
 *
 * 1. 系统要求：本 app 录音时会启动 `microphone` 型 FGS，而「从后台启动 FGS」
 *    在 Android 12+ 受严格限制。经 [RecordTriggerActivity]（透明 Activity）
 *    拉起本服务后，进程已被判定为「使用中」，此限制不再生效。
 * 2. 进程保活：服务处于前台，录音期间进程不易被系统回收。
 *
 * ## 安全：只接受受信任调用方
 *
 * 本服务 `exported=true`（root 守护进程以 shell uid 2000 通过 `am` 调用，
 * `exported=false` 会被系统拒绝：`Requires permission not exported from uid 10216`）。
 * 因此必须在服务内**自行校验调用方 UID**，只允许：
 * - `uid == 0`（root，KernelSU 下的 `su` 命令）；
 * - `uid == 2000`（shell，`adb`/`am` 命令）；
 * - 本 app 自身 UID（[RecordTriggerActivity] 内部启动）。
 *
 * 校验用反射读 `ActivityManager.getLaunchedFromUid(packageName)`（隐藏 API，
 * 拿不到时回落 `Binder.getCallingUid()`）；取到 -1 视为不可信，直接拒绝。
 *
 * ## 命令时序
 *
 * 冷启动第一次触发时，引擎刚创建、Dart 入口尚未跑完。此时命令由
 * [RecordTriggerChannel.deliver] 先落盘，Dart 侧 `consumePending` 补取，
 * 因此**命令不会丢**。
 */
class RecordTriggerService : Service() {

    companion object {
        private const val TAG = "RecordTriggerService"

        /** 命令：开始录音。 */
        const val CMD_START = "start"

        /** 命令：停止录音。 */
        const val CMD_STOP = "stop"

        /** 命令：切换（空闲→开始，录音中→停止）。默认值。 */
        const val CMD_TOGGLE = "toggle"

        /** Intent 里携带命令的 key（与 [RecordTriggerActivity.EXTRA_CMD] 一致）。 */
        const val EXTRA_CMD = "cmd"

        private const val NOTIFICATION_CHANNEL_ID = "feathernote_trigger"
        private const val NOTIFICATION_ID = 257
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // ⚠️ 必须在 onStartCommand 最开始就进入前台，否则系统会在 5 秒内
        // 抛出 ANR/异常（Android 8+ 对 startForegroundService 的硬性要求）。
        startForegroundCompat()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isTrustedCaller()) {
            Log.w(TAG, "拒绝来自不可信 UID 的触发请求（callingUid=${callingUidCompat()}）")
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        val cmd = intent?.getStringExtra(EXTRA_CMD) ?: CMD_TOGGLE
        Log.i(TAG, "收到静默录音命令：$cmd")

        // 立即拿到（必要时创建）进程级引擎，并确保 Dart 入口已跑。
        val app = application as FeatherNoteApplication
        val engine = FeatherNoteApplication.ensureEngine(app)
        // 无界面入口：本服务没有任何 FlutterView，必须走 headlessMain。
        FeatherNoteApplication.ensureDartStarted(engine, headless = true)

        // 命令投递给 Dart（未就绪则落盘等待 consumePending）。
        RecordTriggerChannel.deliver(engine, this, cmd)

        // 服务使命已完成：命令已交给 Dart，不长期占用前台服务
        //（录音自身的 FGS 由 Dart 侧 flutter_foreground_task 管理）。
        stopSelfResult(startId)
        return START_NOT_STICKY
    }

    // ── 前台通知 ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "按键触发",
            NotificationManager.IMPORTANCE_MIN, // 最低优先级，不打扰用户
        ).apply {
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(channel)
    }

    private fun startForegroundCompat() {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("声羽")
            .setContentText("正在处理按键触发…")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ── 调用方校验 ────────────────────────────────────────────────────────

    private fun callingUidCompat(): Int = try {
        android.os.Binder.getCallingUid()
    } catch (_: Throwable) {
        -1
    }

    /**
     * 是否来自受信任调用方（root / shell / 自身）。
     *
     * `getLaunchedFromUid` 是隐藏 API，用反射读取；失败时回落 `Binder.getCallingUid()`。
     * 两者都拿不到（-1）时**拒绝**，遵循最小权限原则。
     */
    private fun isTrustedCaller(): Boolean {
        val selfUid = applicationInfo.uid
        val candidates = mutableListOf<Int>()

        // 1) 隐藏 API：拿「谁启动了本服务」，跨进程（am）场景更准确。
        try {
            val amClass = Class.forName("android.app.ActivityManager")
            val method = amClass.getMethod("getLaunchedFromUid", String::class.java)
            val am = getSystemService(ACTIVITY_SERVICE)
            val uid = method.invoke(am, packageName) as? Int
            if (uid != null && uid >= 0) candidates.add(uid)
        } catch (_: Throwable) {
            // 隐藏 API 不可用（部分 ROM 移除），走回落。
        }

        // 2) 回落：Binder 调用方 UID。
        val binderUid = callingUidCompat()
        if (binderUid >= 0) candidates.add(binderUid)

        if (candidates.isEmpty()) {
            Log.w(TAG, "无法确定调用方 UID，按不可信处理")
            return false
        }

        for (uid in candidates) {
            when (uid) {
                0, // root
                2000, // shell（adb / am）
                selfUid, // 本 app 自身（RecordTriggerActivity）
                -> return true
            }
        }
        Log.w(TAG, "调用方 UID 不在白名单：$candidates（self=$selfUid）")
        return false
    }
}
