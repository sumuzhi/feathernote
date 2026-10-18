# 智能按键「息屏静默录音」技术方案与实施记录

> 状态：**已实施并真机验收通过**（一加 13T / PKX110 / ColorOS 15.0.2.401 / Android 15）
> 版本：App `1.0.20+21`，KernelSU 模块 `feathernote-keytrigger 1.0.0`
> 最后更新：2026-10-18

---

## 一、需求

手机除音量键、电源键外还有一个「智能键」（一加称为 **Action Button**）。需求：

1. **长按该键 3 秒** → 启动本地录音 app 开始录音；
2. **录音中再长按 3 秒** → 立即停止录音并进入纪要生成；
3. 全程**不亮屏、不显示任何界面**、不需要解锁；
4. 不得破坏该键已有的功能（用户已用 Xposed Edge Pro 绑定「双击开手电筒」）；
5. 手机已 root（KernelSU Next），允许任意技术手段。

---

## 二、核心难点与结论（先说结论）

Android 11+ 把 `RECORD_AUDIO` 定义为 **while-in-use 权限**：进程必须被系统判定为
「使用中」，否则 `AudioRecord` 会**静默返回全零数据**（不报错、不抛异常，只是没有声音）。

实测证据（一加 13T / Android 15）：

```
APSMuteRec1 allowCapture[0] hasOp[0] canCaptureIfInCallOrCommunication[1]
  UidState[19] ... isTopOrLatestActive[1] isA11yOnTop[0]
  W ActivityManager: Foreground service started from background can not have
    location/camera/microphone access
```

`allowCapture[0]` 就是最终拒绝裁决。**这不是「权限没给够」**——麦克风在权限模型上
根本不存在「始终允许」选项（系统权限页只有：使用时允许 / 每次询问 / 不允许）。

### 已排除的方案（都有实测数据）

| 方案 | 结论 | 证据 |
|---|---|---|
| root 直接改 appops `RECORD_AUDIO=allow` | ❌ 无效 | 命令返回 `rc=0`，但 `Uid mode` 仍是 `foreground`（系统静默忽略；`CAMERA` 同样如此，是 AOSP 硬编码） |
| ALSA 直采（`tinycap`） | ❌ 无数据 | 所有 capture 节点 `Captured 0 frames`；麦克风数据根本没进 DSP |
| 无障碍服务（含 `TYPE_ACCESSIBILITY_OVERLAY`） | ❌ 无效 | `isA11yOnTop` 恒为 0；即使 app UID 已进入 `Accessibility UIDs` 集合也无用 |
| 悬浮窗 `SYSTEM_ALERT_WINDOW` | ❌ 授权被锁 | ColorOS 下 `appops set` 返回成功但不生效；且需用户手动授权 |

### 有效方案：透明 Activity

**厂商自带录音机 `com.coloros.soundrecorder` 的智能键入口就是 `TransparentActivity`**：

```
oplus.intent.action.START_RECORD_FROM_CUBE_BUTTON:
    com.coloros.soundrecorder/oplus.multimedia.soundrecorder.slidebar.TransparentActivity
```

实测该系统录音机**在息屏下能正常录音**（音频文件持续增长），且它**没有任何特权权限**
（安装在 `/data/app`，`RECORD_AUDIO` 与普通 app 一样）。

**结论**：只要进程里出现过一个（哪怕 1×1 全透明、肉眼不可见的）Activity，
系统就把进程判定为「使用中」，随后启动的 `microphone` 型前台服务就不再算
「后台启动」，麦克风正常。这就是本方案的技术基石。

**关键实测数据对比**：

| 方案 | 屏幕 | 峰值 | 静音秒 |
|---|---|---|---|
| 后台服务直接录音 | 息屏 | 0 / 0 / 0 | 持续增长 |
| **透明 Activity** | **息屏** | **581 / 711 / 4774** | **0** |

---

## 三、系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│ root 侧（KernelSU 模块）                                          │
│                                                                   │
│  keytriggerd  ──读取──▶ /dev/input/event0 (gpio-keys)            │
│  （常驻守护进程）        BTN_TRIGGER_HAPPY32 = 735                │
│       │                                                           │
│       │ 按住 2000ms → 轻震（预提示）                              │
│       │ 按住 3000ms → 触发                                        │
│       ▼                                                           │
│  震动反馈（cmd vibrator_manager）                                 │
│  读取 app 状态文件 → 决定「开始」还是「停止」                       │
│       │                                                           │
│       │ am start --es cmd <start|stop>                            │
│       ▼                                                           │
├─────────────────────────────────────────────────────────────────┤
│ app 侧                                                            │
│                                                                   │
│  RecordTriggerActivity（1×1 全透明，只活一瞬间）                   │
│       │ 趁自己还在前台，启动前台服务                                │
│       ▼                                                           │
│  RecordTriggerService（校验调用方 UID）                           │
│       │ 确保 Dart 入口已跑（headlessMain）                         │
│       ▼                                                           │
│  RecordTriggerChannel（命令投递，落盘兜底）                         │
│       ▼                                                           │
│  RecordTriggerController（Dart 状态机，防抖 3s）                   │
│       ▼                                                           │
│  RecorderController.startRecording() / stopAndGenerate()          │
│       ▼                                                           │
│  麦克风采集 ──▶ 实时 ASR ──▶ 纪要生成（既有链路，一行未改）          │
└─────────────────────────────────────────────────────────────────┘
```

### 时序（长按开始录音）

```
用户按住键
  │
  ├─ t=0ms      keytriggerd 读到 DOWN，记单调时钟起点
  ├─ t=2000ms   震动 25ms（预提示：快触发了）
  ├─ t=3000ms   读取状态文件 = idle → 判定为「开始」
  │             执行 am start RecordTriggerActivity --es cmd start
  ├─             透明 Activity onCreate → 启动 RecordTriggerService → finish()
  ├─             Service 校验调用方 UID → 创建/复用缓存引擎 → headlessMain
  ├─             Dart 消费命令 → 检查麦克风权限（headless 直查）→ 开始录音
  └─             双短震动（45ms × 2）告知用户「已开始」
```

---

## 四、代码改动清单

### 4.1 新增文件

| 文件 | 作用 |
|---|---|
| `android/.../FeatherNoteApplication.kt` | 进程级缓存 `FlutterEngine`；`ensureEngine` / `ensureDartStarted`（headless 与 UI 双入口选择） |
| `android/.../RecordTriggerActivity.kt` | **核心**：1×1 全透明 Activity，只负责「让进程变成使用中」并启动服务，随即 `finish()` |
| `android/.../RecordTriggerService.kt` | 前台服务；校验调用方 UID（root/shell/自身）；把命令交给 Dart |
| `android/.../RecordTriggerChannel.kt` | MethodChannel 桥接（`feathernote/record_trigger`）；命令落盘兜底；状态同步；麦克风权限直查 |
| `android/.../res/values/record_trigger_styles.xml` | `TransparentLaunchTheme`（全透明、无动画、无预览） |
| `lib/core/platform/runtime_mode.dart` | `isHeadlessMode` / `isUiAttached` 进程级标志 |
| `lib/platform/record_trigger_channel.dart` | Dart 侧通道封装；`TriggerCommand` 枚举；命令流 / UI 附着流 |
| `lib/ui/providers/record_trigger_controller.dart` | 触发控制器：防抖 3s、忙碌保护、按当前相位解析 start/stop |

### 4.2 修改文件

| 文件 | 改动 |
|---|---|
| `AndroidManifest.xml` | `application` 改为 `.FeatherNoteApplication`；新增透明 Activity + 触发 Service（含详细注释说明为何 `exported=true`） |
| `MainActivity.kt` | 改用缓存引擎（`getCachedEngineId` / `shouldDestroyEngineWithHost=false`）；`onResume` 通知 UI 附着；不再调用 `super.configureFlutterEngine`（避免插件重复注册） |
| `lib/main.dart` | 拆分双入口 `main()` / `headlessMain()`；进程级 `ProviderContainer`；UI 补挂机制；后端预热 |
| `lib/core/platform/mic_source.dart` | headless 下绕过 `record` 插件的 `hasPermission()`（它在 activity==null 时恒返回 false），改走原生直查 |
| `lib/core/platform/recording_foreground_service.dart` | headless 下跳过 `requestNotificationPermission` / `requestIgnoreBatteryOptimization`（无 Activity 会抛 `ActivityNotAttachedException`） |
| `pubspec.yaml` | 版本 `1.0.19+20` → `1.0.20+21` |

### 4.3 KernelSU 模块（独立目录，未纳入本仓库）

位置：`/Users/sumuzhi/dsh/feathernote-keytrigger/`

| 文件 | 说明 |
|---|---|
| `src/keytriggerd.c` | 守护进程源码（~390 行，含大量注释解释设计决策） |
| `build.sh` | NDK 交叉编译（`aarch64-linux-android24-clang -O2 -Werror -fPIE -pie`） |
| `module/module.prop` | 模块元信息 |
| `module/service.sh` | watchdog：每 2 秒检查守护进程，不在则拉起 |
| `module/config` | 可调阈值（`LONG_PRESS_MS` / `PRE_HINT_MS` / `COOLDOWN_MS`） |
| `module/keytriggerd` | 编译产物（aarch64 PIE，13KB） |

---

## 五、关键技术决策与理由

### 5.1 为什么用 root 守护进程读 evdev，而不是无障碍服务

- 无障碍 `onKeyEvent` **拿不到**该智能键（ColorOS 系统层拦截）；
- 息屏时 Android 输入管线**根本不分发**按键给无障碍服务；
- 直接读 `/dev/input/event0` 是唯一在**息屏**下可靠拿到按键的方式。

**不破坏现有功能**：evdev 支持多读者，本进程 `open` 不独占、不调用 `EVIOCGRAB`，
system_server 与 Xposed Edge Pro 可同时读取（实测双击手电筒正常）。

### 5.2 为什么 `O_NONBLOCK` 是必须的（踩过的坑）

最初用阻塞 fd，内层 `read()` 会卡住，外层 `poll()` 的超时永远不生效，
导致「按住 3 秒」判定退化为「松开才判定」——日志里 3679ms 的按住被记为
「松手取消」。改用 `O_NONBLOCK` + 读空循环后正常。

### 5.3 为什么透明 Activity 要 `exported=true`

root 守护进程通过 `am` 调用，而 `am` 以 shell uid(2000) 运行。`exported=false`
会被系统拒绝：`Requires permission not exported from uid 10216`。
因此服务内部**自行校验调用方 UID**（只允许 0/2000/自身），遵循最小权限原则。

### 5.4 为什么需要进程级缓存引擎

- 录音可能在**无界面**时启动，常规 Flutter 的引擎绑定在 Activity 上，Activity 销毁即引擎销毁；
- 无界面录音与用户打开的界面**必须共享同一个 Dart isolate / Riverpod 容器**，
  否则会出现「后台在录、打开 app 显示空闲」的状态分裂。

### 5.5 为什么命令要落盘

冷启动时 `am start` 到达时 Dart 入口可能尚未跑完。命令先写入
`files/pending_trigger`，Dart 侧启动后 `consumePending()` 补取，**保证第一次长按不丢**。

### 5.6 为什么震动语义由状态文件决定

用户需要「盲操作」时靠震动区分当前动作：
- 开始 = 双短震（45ms × 2）
- 停止 = 一长震（260ms）
- 预提示 = 轻震（25ms）
- 失败 = 三连震

守护进程读取 app 写入的 `files/trigger_state`（`recording` / `idle`）判断当前该执行哪种。

---

## 六、真机验收结果

全部测试在一加 13T（PKX110）真机完成：

| # | 测试项 | 结果 |
|---|---|---|
| 1 | 短按 851ms 不触发 | ✅ 日志「松手取消」，无误录 |
| 2 | **息屏长按 3s → 静默录音** | ✅ 屏幕保持 `Dozing`，峰值 638，前台无任何 app 界面 |
| 3 | 录音中长按 → 停止并生成纪要 | ✅ 收尾 253ms，纪要生成成功（363 字） |
| 4 | 双击手电筒不受影响 | ✅ `led:switch_2` 正常 0→1→0 |
| 5 | 锁屏状态长按 | ✅ 峰值 12996，正常录音 |
| 6 | 长时间录音（63 秒） | ✅ 稳定，峰值 573，无静音 |
| 7 | **进程完全退出后冷启动** | ✅ 峰值 30941，headless 入口正确 |
| 8 | 守护进程被杀自动重启 | ✅ watchdog 拉起（新 PID），功能正常 |
| 9 | 实时 ASR 转写 | ✅ 息屏录音下正常输出识别文本 |
| 10 | 录音中打开 app 查看实时状态 | ✅ 用户验证通过 |

---

## 七、运维与回滚

### 查看状态

```bash
# 守护进程是否在跑
adb shell su -c 'ps -A -o PID,PPID,NAME | grep keytriggerd'

# 触发日志（含按住时长、触发判定、失败原因）
adb shell su -c 'tail -20 /data/adb/modules/feathernote-keytrigger/keytriggerd.log'

# 当前录音状态
adb shell su -c 'cat /data/user/0/com.feathernote.app/files/trigger_state'
```

### 调整阈值

编辑 `/data/adb/modules/feathernote-keytrigger/config`：

```
LONG_PRESS_MS=3000   # 长按触发阈值
PRE_HINT_MS=2000     # 预提示震动时刻
COOLDOWN_MS=2000     # 触发冷却
```

改完重启守护进程即可生效（`pkill -f keytriggerd`，watchdog 会自动拉起）。

### 回滚

**只关功能**（保留 app）：
在 KernelSU Manager 中禁用 `feathernote-keytrigger` 模块，重启。

**完全恢复原状**：
1. KernelSU Manager 禁用模块；
2. 卸载 app，重装原始 `1.0.19` 包（`apk-share/feathernote-release-1010-1434-539dac1-arm64.apk`）；
3. 代码侧 `git checkout -- .` 并删除新增文件，或 `git reset --hard 9e2eef3`。

---

## 八、已知限制

1. **必须 root**：依赖读取 `/dev/input/event0`，非 root 无法在息屏下拿到按键。
2. **依赖透明 Activity 手法**：若未来 Android 版本进一步收紧
   （例如禁止透明 Activity 触发 while-in-use 豁免），本方案会失效，需重新评估。
3. **首次使用需授权麦克风**：用户首次打开 app 录音时需授予一次麦克风权限；
   之后长按触发路径可直接复用（headless 下走原生直查）。
4. **电池优化**：建议将 app 加入电池优化白名单（app 内有引导），
   否则部分国产 ROM 可能在高负载下回收进程（前台服务已大幅降低该风险）。

---

## 九、相关文件索引

- 守护进程源码：`/Users/sumuzhi/dsh/feathernote-keytrigger/src/keytriggerd.c`
- 模块打包：`/Users/sumuzhi/dsh/feathernote-keytrigger/module/`
- app 侧入口：`lib/main.dart`（`main` / `headlessMain`）
- 核心原生组件：`android/app/src/main/kotlin/com/smartminutes/smart_minutes_flutter/RecordTrigger*.kt`
- 构建脚本：`scripts/run_real.sh`（注入真实百炼 API Key）
