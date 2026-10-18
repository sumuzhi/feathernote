package com.smartminutes.smart_minutes_flutter

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 主界面 Activity。
 *
 * 与常规 Flutter 应用的关键差异：**复用进程级缓存引擎**，而不是自建引擎。
 *
 * 原因（「智能按键息屏静默录音」所需）：
 * - 进程可能已经因按键触发而启动（headless 跑着 [FeatherNoteApplication] 的
 *   缓存引擎、正在录音）；
 * - 此时用户打开 app，必须挂到**同一个** Dart isolate 上，才能看到正在进行的
 *   录音状态，而不是显示空闲。
 *
 * 因此：
 * 1. [getCachedEngineId] 返回缓存引擎 ID，Flutter 会复用它；
 * 2. [shouldDestroyEngineWithHost] 返回 false，Activity 销毁时**不销毁引擎**
 *   （否则退回桌面就会中断录音）；
 * 3. [ensureDartStarted] 保证 Dart 入口已跑（进程可能是 headless 起来的，
 *   也可能还没起）；
 * 4. `onResume` 通知 Dart 侧「UI 已附着」，让 headless 状态补挂 `runApp`。
 */
class MainActivity : FlutterActivity() {

    /** 复用 [FeatherNoteApplication] 创建的缓存引擎。 */
    override fun getCachedEngineId(): String = FeatherNoteApplication.ENGINE_ID

    /** Activity 销毁时**不**销毁引擎——录音需要在退出界面后继续。 */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // 先把引擎准备好（getCachedEngineId 之后 Flutter 会自己取，但这里要
        // 确保它已被创建并注册好插件）。
        val engine = FeatherNoteApplication.ensureEngine(application)
        // 进程若因按键触发而 headless 起来，Dart 已在跑；否则从这里启动 UI 入口。
        FeatherNoteApplication.ensureDartStarted(engine, headless = false)
        super.onCreate(savedInstanceState)
    }

    /**
     * ⚠️ **不再调用 `super.configureFlutterEngine`**。
     *
     * 使用缓存引擎时，嵌入层已经注册过插件；再次调用会抛
     * `Attempted to register plugin ... already registered`（真机实测）。
     * 这里只注册仍需要 Activity 上下文的插件。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 导入音视频通道需要 Activity 上下文（文件选择器）。
        ApkInstallerPlugin.register(flutterEngine, this)
    }

    /**
     * UI 已附着：通知 Dart 侧补挂 `runApp`（headless → 有界面 的切换点）。
     */
    override fun onResume() {
        super.onResume()
        FeatherNoteApplication.engine?.let { engine ->
            RecordTriggerChannel.notifyUiAttached(engine)
        }
    }
}
