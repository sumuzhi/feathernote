# 声羽 FeatherNote（smart-minutes-flutter）

> 听见每一场会议的重点 —— 录音 → 实时转写 → AI 纪要 → 多格式导出的 Flutter 会议纪要应用。

声羽 FeatherNote 是 [smart-minutes](../smart-minutes)（Web 端智能语音会议纪要系统）的 **Flutter 原生重写版**，采用 **方案 B：Dart-native 进程内后端**——语音识别、纪要生成、存储全部跑在 App 进程内，**无独立服务器依赖**，适合侧载分发的 Android 自用形态。

## 功能特性

- 🎙️ **实时录音转写**：百炼 DashScope 流式 ASR（`qwen-audio-3.0-asr-flash-streaming`），逐句上屏、说话人分轨、断流/静音双看门狗
- ⏸️ **暂停/恢复**：短暂停 15s 保活、长停挂起重开会话（`taskBaseMs` 时间补偿，段不重不漏）
- 📝 **AI 会议纪要**：终稿转写（`qwen-audio-3.1-asr-flash-filetrans`）+ LLM 摘要（`qwen3.7-plus`，知识抽取式 Prompt 策略层）
- ▶️ **逐段回放**：单 WAV 流式追加（暂停零数据，无需拼接）、段级进度条、自动停在段尾、断点续播
- 📤 **多格式导出**：Markdown / PDF / Word / TXT，支持系统分享与 MediaStore 落盘（Download/SmartMinutes/）
- 🔍 **搜索与筛选**：关键词高亮定位、说话人筛选、历史页状态缓存（筛选/滚动位置跨页保留）
- 📊 **统计**：会议次数与累计时长（0.xh 一位小数）
- 🚀 **快速进入**：静态启动页 + 后端就绪即进首页，MediaStore 初始化不阻塞首帧

## 技术架构

```
UI（Flutter / Riverpod 3 / go_router 18）
        │  唯一类型化门面 BackendApi（进程内直调，无 HTTP）
        ▼
Services（录音编排 / 实时 ASR WebSocket / filetrans 轮询 / 纪要生成 / 导出）
        │
        ▼
存储（sqlite3 FFI 本地库）  云端（百炼 DashScope：ASR + LLM，region cn-beijing）
```

- **方案 B（Dart-native）**：不再内嵌 Node.js，后端逻辑全部 Dart 重写；`--dart-define=ENABLE_LOCAL_HTTP=true` 可选开启 debug-only 的 localhost HTTP 薄适配层
- **密钥安全**：`DASHSCOPE_API_KEY` 只存本地 `.env`（已 gitignore），构建时经 `--dart-define` 注入编译期常量；**必须走 `const String.fromEnvironment`**（非 const 调用在 AOT 下不折叠，值不会进包——见 `lib/core/config/secrets.dart` 注释）
- **启动校验**：缺 Key 时显式降级 MockEngine 并在顶部横幅提示原因，不静默失败

## 目录结构

```
lib/
├── app/                  # 应用根（主题 / 路由 / Toast 浮层）
├── core/
│   ├── config/           # AppConfig + Secrets（编译期注入）
│   ├── log/              # 结构化日志（info 起关键链路全埋点）
│   └── pcm/              # PCM 电平检测（静音/断流两分法）
├── backend/              # Dart-native 后端（DI / engine / services / storage）
├── domain/               # 领域模型（Meeting / Segment / Speaker）
└── ui/
    ├── pages/            # 页面逻辑层（状态映射 → 视图模型）
    ├── screens/          # 屏幕骨架（对齐设计稿 1:1）
    ├── providers/        # Riverpod 状态（录音 / 播放 / 历史）
    ├── widgets/          # 通用组件（转写条目 / 进度条 / Toast …）
    └── router/           # go_router 路由表 + 返回键接管
scripts/run_real.sh       # 真实数据运行 / 打包入口（Key 校验 + 注入 + 构建戳）
apk-share/                # 侧载分发静态下载页（构建产物 + 版本核对）
test/                     # 227 个测试（单元 + 组件 + 录制/播放/终稿链路）
```

## 快速开始

### 环境要求

| 组件 | 版本 |
|------|------|
| Flutter | 3.47.5 stable（Dart 3.13.4） |
| Android SDK | compileSdk 37（部分插件要求） |
| JDK | 21（AGP 9 最高支持 Java 24，勿用更高） |
| 目标平台 | **仅 Android arm64**（实时链路与本地存储依赖 `dart:io`，Web/桌面不可用） |

### 配置密钥

项目根目录创建 `.env`（已 gitignore，绝不入库）：

```dotenv
DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxx
# 可选
BAILIAN_REGION=cn-beijing
BAILIAN_FILETRANS_MODEL=qwen-audio-3.1-asr-flash-filetrans
BAILIAN_LLM_MODEL=qwen3.7-plus
```

### 运行 / 打包

```bash
# 模拟器或真机运行（自动选设备）
./scripts/run_real.sh

# 打包（--split-per-abi，arm64；自动注入密钥与构建戳 月日-时分/短哈希）
./scripts/run_real.sh build-release   # Release（约 30MB，橙底图标）
./scripts/run_real.sh build-debug     # Debug（深棕底图标，可与 Release 并存）
```

脚本内置：Key 格式校验（sk- 前缀 + 长度越界中止）、实时模型白名单回退告警、构建戳注入。产物在 `build/app/outputs/flutter-apk/`，侧载分发用 `apk-share/`（含带版本核对块的下载页）。

### 测试

```bash
flutter test      # 227 个用例全绿
flutter analyze   # 0 error
```

> 本机若设了 `HTTP_PROXY`，flutter_tester 的 localhost WebSocket 会被劫持，请：
> `env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY="127.0.0.1,localhost,::1" flutter test`

## 版本核对

App「设置」页底部版本行显示构建戳（如 `0926-1355/d0f81c1`），与下载页版本信息块一致即为最新构建。注意：构建戳经 `const String.fromEnvironment` 编译期注入（见上文密钥安全说明）。

## 已知限制

- **仅 Android arm64**：`armeabi-v7a` / `x86_64` 无预编译产物，不支持
- **模拟器音频怪癖**：AudioTrack 时钟偶发快进（`device stall time corrected`），进度条走速与时长截断在模拟器上有假阳性，音频正确性一律以真机为准
- **知识库（KB）特性未实现**：入口已按「隐藏不删除」策略收敛
- **filetrans 终稿**在模拟器无有效语音时会报 `ASR_RESPONSE_HAVE_NO_WORDS`，需真机验证

## 许可与致谢

个人项目，未附开源许可。语音与摘要能力由 [阿里云百炼（DashScope）](https://help.aliyun.com/zh/model-studio/) 提供。
