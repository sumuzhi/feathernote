#!/usr/bin/env bash
# 用「真实百炼数据」构建 / 运行 声羽 FeatherNote。
#
# 背景：App 启动时会做配置强校验（lib/core/config/app_config.dart 的 validate()），
# 缺少 DASHSCOPE_API_KEY 时不会静默失败，而是 **显式降级到 MockEngine**
# （lib/backend/di.dart:70-72），并在顶部横幅提示降级原因。
# 因此「想用真实数据」= 把有效 Key 通过 --dart-define 注入编译期常量。
#
# 密钥从 **本项目根目录的 .env** 读取（不再读原项目 smart-minutes/server/.env），
# **不硬编码、不打印、不入库**（.gitignore 已排除 .env / .env.*）。
#
# 用法：
#   ./scripts/run_real.sh              # flutter run（自动选设备，含 Android 模拟器）
#   ./scripts/run_real.sh build-debug  # flutter build apk --debug  （arm64）
#   ./scripts/run_real.sh build-release# flutter build apk --release（arm64）
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${SM_ENV_FILE:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "找不到环境文件：$ENV_FILE"
  echo "请在项目根目录创建 .env（含 DASHSCOPE_API_KEY=sk-... 等配置）"
  exit 1
fi

# 载入 .env（set -a 让所有变量导出）
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ -z "${DASHSCOPE_API_KEY:-}" ]]; then
  echo "$ENV_FILE 里 DASHSCOPE_API_KEY 为空，无法使用真实引擎"
  exit 1
fi

# ── Key 注入校验（历史缺陷：注入值曾被污染成 414 字符 → 服务端 401） ────────
# 合法 DashScope Key：sk- 前缀 + 20~200 字符。越界即中止构建，绝不带着脏值出包。
KEY_LEN=${#DASHSCOPE_API_KEY}
if [[ "$KEY_LEN" -lt 20 || "$KEY_LEN" -gt 200 ]]; then
  echo "❌ DASHSCOPE_API_KEY 长度异常（$KEY_LEN 字符，合法 20~200），中止构建。"
  echo "   请检查 $ENV_FILE 中该值是否被污染（换行 / 引号 / 注释粘进值里）。"
  exit 1
fi
if [[ "$DASHSCOPE_API_KEY" != sk-* ]]; then
  echo "❌ DASHSCOPE_API_KEY 未以 sk- 开头（疑似污染值），中止构建。"
  exit 1
fi

# ── 实时模型白名单回退（根因防护） ───────────────────────────────────────────
# 百炼 ASR 的「实时(streaming/realtime)」与「终稿(filetrans)」是**两套不同**白名单。
# 历史 .env 里 BAILIAN_REALTIME_MODEL=qwen-audio-3.1-asr-flash-streaming，
# 但 3.1 只存在于 filetrans 线 —— 实时线**不存在**该模型 → 服务端 run-task 被拒
# → 帧全堆在待发队列 → **实时零句子 → 逐字稿为空**。
# 策略：不在白名单 → 醒目警告 + 回退到白名单默认值；在白名单 → 尊重用户设置。
KNOWN_REALTIME_MODELS=(
  "qwen-audio-3.0-asr-flash-streaming"
  "qwen3-asr-flash-realtime"
  "fun-asr-realtime"
  "fun-asr-mtl-realtime"
  "fun-asr-flash-8k-realtime"
  "paraformer-realtime-v2"
  "paraformer-realtime-v1"
  "paraformer-realtime-8k-v2"
  "paraformer-realtime-8k-v1"
)
REALTIME_MODEL_DEFAULT="qwen-audio-3.0-asr-flash-streaming"

REALTIME_MODEL_ORIG="${BAILIAN_REALTIME_MODEL:-}"
REALTIME_MODEL_EFFECTIVE="$REALTIME_MODEL_DEFAULT"
REALTIME_MODEL_FELLBACK=0
if [[ -n "$REALTIME_MODEL_ORIG" ]]; then
  for model in "${KNOWN_REALTIME_MODELS[@]}"; do
    if [[ "$REALTIME_MODEL_ORIG" == "$model" ]]; then
      REALTIME_MODEL_EFFECTIVE="$REALTIME_MODEL_ORIG"
      break
    fi
  done
  if [[ "$REALTIME_MODEL_EFFECTIVE" != "$REALTIME_MODEL_ORIG" ]]; then
    REALTIME_MODEL_FELLBACK=1
  fi
fi
# 用收敛后的值覆盖环境变量，供 --dart-define 与回显统一使用。
BAILIAN_REALTIME_MODEL="$REALTIME_MODEL_EFFECTIVE"
export BAILIAN_REALTIME_MODEL

FLUTTER="${FLUTTER_BIN:-/Users/sumuzhi/.workbuddy/binaries/flutter/flutter/bin/flutter}"

# 每个 --dart-define 作为独立数组元素（值经双引号注入，shell 展开一次后定型）。
DEFINES=(
  "--dart-define=DASHSCOPE_API_KEY=$DASHSCOPE_API_KEY"
  "--dart-define=DASHSCOPE_WORKSPACE_ID=${DASHSCOPE_WORKSPACE_ID:-}"
  "--dart-define=BAILIAN_REGION=${BAILIAN_REGION:-cn-beijing}"
  # 实时模型：取自上面的白名单回退结果（REALTIME_MODEL_EFFECTIVE 必在白名单内）。
  "--dart-define=BAILIAN_REALTIME_MODEL=${REALTIME_MODEL_EFFECTIVE}"
  "--dart-define=BAILIAN_FILETRANS_MODEL=${BAILIAN_FILETRANS_MODEL:-qwen-audio-3.1-asr-flash-filetrans}"
  "--dart-define=BAILIAN_LLM_MODEL=${BAILIAN_LLM_MODEL:-qwen3.7-plus}"
  "--dart-define=ENGINE_PROVIDER=${ENGINE_PROVIDER:-bailian}"
  # 诊断日志级别：debug 下会额外打印更细的链路埋点。
  # 关键环节（起录各步 / 首帧 / 每秒音频诊断 / WS URL 与 task-started /
  # task-failed / filetrans 各步 / 纪要首字节 / 链路摘要）都用 **info 级**，
  # 即使不设 debug 也能看到；这里设 debug 是为了拿到最全的现场。
  "--dart-define=LOG_LEVEL=${LOG_LEVEL:-debug}"
  # 构建戳（自动：月日-时分 / git 短哈希；可用 BUILD_STAMP=... 覆盖）。
  "--dart-define=BUILD_STAMP=${BUILD_STAMP:-$(date +%m%d-%H%M)/$(git rev-parse --short HEAD)}"
)

echo "已注入真实百炼配置："
echo "  region        = ${BAILIAN_REGION:-cn-beijing}"
if [[ "$REALTIME_MODEL_FELLBACK" -eq 1 ]]; then
  echo "  ⚠️  realtime      = ${REALTIME_MODEL_EFFECTIVE}"
  echo "                  ↳ 已回退！原值 \"${REALTIME_MODEL_ORIG}\" 不在实时模型白名单内（疑似非法模型名），已改用默认值"
elif [[ -z "$REALTIME_MODEL_ORIG" ]]; then
  echo "  realtime      = ${REALTIME_MODEL_EFFECTIVE}  （.env 未设置，采用默认值）"
else
  echo "  realtime      = ${REALTIME_MODEL_EFFECTIVE}  （来自 .env，白名单校验通过）"
fi
echo "  filetrans     = ${BAILIAN_FILETRANS_MODEL:-qwen-audio-3.1-asr-flash-filetrans}"
echo "  llm           = ${BAILIAN_LLM_MODEL:-qwen3.7-plus}"
echo "  log level     = ${LOG_LEVEL:-debug}"
echo "  api key 长度  = ${KEY_LEN}（值不打印；运行时可用 logcat 中 Authorization 的 len 核对）"
echo "  build stamp   = ${BUILD_STAMP:-自动生成}"
echo "  ↑ 实时/终稿是两套白名单：realtime 走 streaming 型号，filetrans 走 filetrans 型号，勿混用"

# ── 构建快照回收（防 .dart_tool 膨胀） ─────────────────────────────────────
# flutter 每换一组 --dart-define（含每次变化的构建戳）就在 .dart_tool/flutter_build/
# 新建一个 ~131MB 的快照目录且从不回收——几十次构建可积累数 GB（2026-09-26 实测
# 5.5G）。构建成功后只保留最新一份快照，其余全部删除。
prune_flutter_snapshots() {
  for dir in .dart_tool/flutter_build .dart_tool/hooks_runner; do
    if [[ ! -d "$dir" ]]; then continue; fi
    # 所有 local 一律**声明即初始化**（`local x` 裸声明在 set -u 下是隐患）。
    local keep="" freed=0 entry=""
    # 只保留 mtime 最新的一个快照**目录**；目录里的零散文件（如 sqlite3）
    # 不可作 keep 锚点，否则会误删真正的快照目录（2026-09-26 实测）。
    for entry in $(ls -t "$dir" 2>/dev/null); do
      if [[ -d "$dir/$entry" ]]; then keep="$entry"; break; fi
    done
    for entry in "$dir"/*; do
      if [[ "$(basename "$entry")" == "$keep" ]]; then continue; fi
      rm -rf "$entry"
      freed=1
    done
    if [[ "$freed" -eq 1 ]]; then
      echo "🧹 已清理 $dir 过期快照（保留最新 $keep）"
    fi
  done
}

CMD="${1:-run}"
case "$CMD" in
  run)
    exec "$FLUTTER" run "${DEFINES[@]}"
    ;;
  build-debug)
    "$FLUTTER" build apk --debug --split-per-abi --target-platform android-arm64 "${DEFINES[@]}"
    prune_flutter_snapshots
    ;;
  build-release)
    "$FLUTTER" build apk --release --split-per-abi --target-platform android-arm64 "${DEFINES[@]}"
    prune_flutter_snapshots
    ;;
  *)
    echo "用法：$0 [run|build-debug|build-release]"
    exit 1
    ;;
esac
