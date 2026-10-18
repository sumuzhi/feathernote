# feathernote-keytrigger（KernelSU / Magisk 模块）

长按一加智能键 3 秒 → 息屏静默开始/停止录音。配套 app 版本 ≥ `1.0.20`。

> 主文档见 [`../docs/FEATURE-KEY-TRIGGER-RECORDING.md`](../docs/FEATURE-KEY-TRIGGER-RECORDING.md)

## 为什么需要 root

一加智能键（`/dev/input/event0` 的 `BTN_TRIGGER_HAPPY32` = code 735）在
**息屏时不会分发给无障碍服务**（实测），只能直接读取 evdev 节点。

本模块**不独占**该设备（不调用 `EVIOCGRAB`），因此 system_server 与
Xposed Edge Pro 仍可正常读取——**双击手电筒等功能不受影响**（实测通过）。

## 目录结构

```
keytrigger-module/
├── src/keytriggerd.c     # 守护进程源码（含详细设计注释）
├── build.sh              # NDK 交叉编译脚本
└── module/
    ├── module.prop       # 模块元信息
    ├── service.sh        # watchdog（每 2 秒检查，进程不在则拉起）
    ├── config            # 可调阈值
    └── keytriggerd       # 编译产物（aarch64 PIE，构建后生成）
```

## 构建

需要 Android NDK（默认路径 `~/Library/Android/sdk/ndk/29.0.14206865`，
可用 `ANDROID_NDK_HOME` 覆盖）：

```bash
./build.sh
# 产物：module/keytriggerd
```

## 安装

```bash
adb push module/* /data/local/tmp/
adb shell su -c 'mkdir -p /data/adb/modules/feathernote-keytrigger && \
  cd /data/local/tmp && cp module.prop config service.sh keytriggerd \
  /data/adb/modules/feathernote-keytrigger/ && \
  chmod 755 /data/adb/modules/feathernote-keytrigger/{service.sh,keytriggerd}'
# 启动（或重启手机）
adb shell su -c 'setsid /data/adb/modules/feathernote-keytrigger/service.sh </dev/null >/dev/null 2>&1 &'
```

> 正式使用请通过 KernelSU Manager 安装 zip 包；`setsid` 方式仅用于调试
> （adb shell 退出时后台进程会被清理，开机自启由 KernelSU 负责）。

## 配置

编辑 `/data/adb/modules/feathernote-keytrigger/config`：

| 配置项 | 默认 | 说明 |
|---|---|---|
| `LONG_PRESS_MS` | `3000` | 长按触发阈值（毫秒），按住满即可触发，无需松手 |
| `PRE_HINT_MS` | `2000` | 预提示震动时刻，必须小于 `LONG_PRESS_MS` |
| `COOLDOWN_MS` | `2000` | 触发后冷却时间，防重复触发 |

改完重启守护进程生效：

```bash
adb shell su -c 'pkill -f keytriggerd'   # watchdog 会在 2 秒内自动拉起
```

## 诊断

```bash
# 守护进程状态
adb shell su -c 'ps -A -o PID,PPID,NAME | grep keytriggerd'

# 触发日志（按住时长 / 触发判定 / 失败原因）
adb shell su -c 'tail -30 /data/adb/modules/feathernote-keytrigger/keytriggerd.log'

# watchdog 日志
adb shell su -c 'tail -20 /data/adb/modules/feathernote-keytrigger/service.log'

# app 当前录音状态
adb shell su -c 'cat /data/user/0/com.feathernote.app/files/trigger_state'
```

## 震动语义

| 场景 | 震动模式 |
|---|---|
| 按住到 2 秒（预提示） | 轻震 25ms |
| 开始录音 | 双短震 45ms × 2 |
| 停止录音 | 一长震 260ms |
| 触发失败（如 app 被卸载） | 三连震 40ms × 3 |

## 卸载

在 KernelSU Manager 中禁用或删除本模块，重启即可。

**注意**：仅禁用模块不会影响 app 正常使用（此时长按功能失效，但 app 内录音一切正常）。
