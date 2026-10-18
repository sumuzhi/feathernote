package com.smartminutes.smart_minutes_flutter

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * 全局 Application：**持有唯一一个 FlutterEngine**。
 *
 * 为什么需要（「智能按键息屏静默录音」的地基）：
 * 常规 Flutter 应用的引擎生命周期绑在 `FlutterActivity` 上——Activity 销毁即引擎销毁。
 * 而本功能要求「无界面时也能录音」，因此引擎必须活在进程级：
 *
 * - 引擎由 [ensureEngine] 创建并缓存（[FlutterEngineCache]），进程存活则引擎存活；
 * - `MainActivity` 与 `RecordTriggerActivity` 都复用这个缓存引擎；
 * - `RecordTriggerService` 直接在这个引擎上执行 Dart 入口，无需 Activity。
 *
 * **单一引擎是刻意的**：无界面录音与用户打开 app 看到的界面必须共享同一个
 * Dart isolate / Riverpod 容器，否则会出现「后台在录、打开 app 显示空闲」的状态分裂。
 *
 * ⚠️ 引擎**不预处理启动**：`onCreate` 里起引擎会拖慢冷启动、每次进程启动白付
 * 一份内存。改为首次需要时才创建（见 [ensureEngine]）。
 */
class FeatherNoteApplication : Application() {

    companion object {
        /** 缓存引擎 ID（MainActivity / RecordTriggerActivity / Service 共用）。 */
        const val ENGINE_ID = "feathernote-main-engine"

        /** 无界面 Dart 入口函数名（见 `lib/main.dart` 的 `headlessMain`）。 */
        private const val HEADLESS_ENTRYPOINT = "headlessMain"

        /** 当前缓存的引擎（供 Activity 查询）。 */
        @JvmStatic
        var engine: FlutterEngine? = null
            private set

        /**
         * 取（必要时创建）进程级缓存引擎。只在主线程调用。
         *
         * 引擎已存在时直接复用——包括「进程因按键触发而 headless 起来」的情形，
         * 此时用户随后打开 app 必须复用同一引擎，才能看到正在进行的录音。
         */
        @JvmStatic
        fun ensureEngine(application: Application): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
                engine = it
                return it
            }

            val created = FlutterEngine(application)
            // 注册全部插件（与 MainActivity 此前使用的完全一致）。
            GeneratedPluginRegistrant.registerWith(created)
            // 本项目的自定义通道。
            RecordTriggerChannel.register(created, application)
            MediaImportPlugin.register(created)

            FlutterEngineCache.getInstance().put(ENGINE_ID, created)
            engine = created
            return created
        }

        /**
         * 确保 Dart 入口已执行（有界面 / 无界面各走各的入口）。
         *
         * - 无界面（按键触发）：没有 FlutterView，`main()` 里的 `runApp()` 会抛
         *   `StateError`，因此走 `headlessMain`（只建容器、不挂 UI）；
         * - 有界面（用户打开 app）：必须走标准 `main()`，它内部会 `runApp`。
         *
         * 一个 isolate 只能执行一次入口，故用 `isExecutingDart` 判重：
         * 进程已因 headless 起来时，用户打开 app 由 `onResume` 通知 Dart 侧补挂 UI。
         *
         * @param headless true=无界面入口，false=标准 UI 入口
         * @return true 表示本次启动了入口；false 表示引擎已在跑 Dart（复用）
         */
        @JvmStatic
        fun ensureDartStarted(engine: FlutterEngine, headless: Boolean): Boolean {
            val executor: DartExecutor = engine.dartExecutor
            if (executor.isExecutingDart) return false
            val defaultEntry = DartExecutor.DartEntrypoint.createDefault()
            val entrypoint = if (headless) {
                DartExecutor.DartEntrypoint(defaultEntry.pathToBundle, HEADLESS_ENTRYPOINT)
            } else {
                defaultEntry
            }
            executor.executeDartEntrypoint(entrypoint)
            return true
        }
    }
}
