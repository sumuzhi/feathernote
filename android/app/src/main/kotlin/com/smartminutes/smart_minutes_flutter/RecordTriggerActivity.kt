package com.smartminutes.smart_minutes_flutter

import android.app.Activity
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.WindowManager

/**
 * **静默录音的「触发器」Activity**：肉眼完全不可见，只存在极短时间。
 *
 * ## 它解决的问题
 *
 * Android 11+ 把 `RECORD_AUDIO` 定义为 **while-in-use 权限**：进程必须处于
 * 「使用中」状态才允许采集麦克风。从后台直接启动 `microphone` 型前台服务时，
 * 系统会拒绝并静默静音（实测日志）：
 *
 * ```
 * W ActivityManager: Foreground service started from background can not have
 *   location/camera/microphone access
 * APSMuteRec1 allowCapture[0] ... isTopOrLatestActive[1]
 * ```
 *
 * 解法与厂商自带录音机一致：**先让进程出现一个（不可见的）Activity**，
 * 进程随即被判定为前台；随后由它启动前台服务，就不再算「后台启动」。
 *
 * 实测依据：`com.coloros.soundrecorder` 的智能键入口
 * `oplus.intent.action.START_RECORD_FROM_CUBE_BUTTON` 指向
 * `oplus.multimedia.soundrecorder.slidebar.TransparentActivity`，
 * 且息屏状态下能正常录音（音频文件持续增长）。而该 Activity 在录音开始后
 * 即被销毁 —— 说明「Activity 存在」只在**启动前台服务那一刻**需要。
 *
 * ## 视觉：完全不可见
 *
 * - 主题 `TransparentLaunchTheme`：全透明、无标题、无动画、无预览；
 * - 窗口尺寸强制 1×1 像素（[makeWindowInvisible] 里用 WindowManager 覆盖）；
 * - `FLAG_NOT_FOCUSABLE` / `FLAG_NOT_TOUCHABLE`：不抢焦点、不可点击；
 * - `excludeFromRecents` + `noHistory`（见 manifest）：不进入最近任务。
 */
class RecordTriggerActivity : Activity() {

    companion object {
        private const val TAG = "RecordTriggerActivity"

        /** 触发命令：与 [RecordTriggerService] 保持一致。 */
        const val EXTRA_CMD = "cmd"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1) 把窗口压到 1×1 全透明（主题之外再兜一层，防个别 ROM 差异）。
        makeWindowInvisible()

        val cmd = intent?.getStringExtra(EXTRA_CMD) ?: RecordTriggerService.CMD_TOGGLE
        Log.i(TAG, "静默触发 Activity 已启动，命令=$cmd（不可见，即将结束）")

        // 2) **趁本 Activity 仍处于前台**，启动录音触发服务。
        //    这是「避免后台启动前台服务」的关键时序：此时进程已被判定为使用中，
        //    随后由服务启动的 microphone 型 FGS 就不会被系统剥夺麦克风。
        try {
            val serviceIntent = android.content.Intent(this, RecordTriggerService::class.java).apply {
                putExtra(EXTRA_CMD, cmd)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            Log.i(TAG, "已请求启动 RecordTriggerService（Activity 仍在前台，麦克风有效）")
        } catch (t: Throwable) {
            Log.e(TAG, "启动 RecordTriggerService 失败", t)
        }

        // 3) 立即退场：Activity 只在「启动服务」这一刻需要。
        finish()
    }

    /**
     * 让本 Activity 的窗口完全不可见：1×1 像素、全透明、不接收触摸。
     *
     * 即使主题已是 Translucent，仍显式设置窗口属性，避免个别 ROM 对
     * `Theme.Translucent` 的处理差异导致可见的空白帧。
     */
    private fun makeWindowInvisible() {
        try {
            window.setBackgroundDrawableResource(android.R.color.transparent)
            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            )
            val params = window.attributes
            params.width = 1
            params.height = 1
            params.alpha = 0f
            params.gravity = Gravity.TOP or Gravity.START
            params.format = PixelFormat.TRANSLUCENT
            window.attributes = params
        } catch (t: Throwable) {
            Log.w(TAG, "设置不可见窗口属性失败（忽略）：${t.message}")
        }
    }
}
