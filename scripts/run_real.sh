#!/usr/bin/env bash
# 用「真实百炼数据」运行 Flutter App。
#
# 背景：App 启动时会做配置强校验（lib/core/config/app_config.dart 的 validate()），
# 缺少 DASHSCOPE_API_KEY 时不会静默失败，而是 **显式降级到 MockEngine**
# （lib/backend/di.dart:70-72），并在顶部横幅提示降级原因。
# 因此「想用真实数据」= 把有效 Key 通过 --dart-define 注入编译期常量。
#
# 密钥从原项目 smart-minutes/server/.env 读取，**不硬编码、不打印、不入库**。
#
# 用法：
#   ./scripts/run_real.sh          # flutter run（自动选设备，含 Android 模拟器）
#   ./scripts/run_real.sh build    # flutter build apk --debug
#   SM_ENV_FILE=/path/to/.env ./scripts/run_real.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${SM_ENV_FILE:-../smart-minutes/server/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "找不到环境文件：$ENV_FILE"
  echo "请设置 SM_ENV_FILE 指向含 DASHSCOPE_API_KEY 的 .env"
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
echo "  api key 长度  = ${#DASHSCOPE_API_KEY}（值不打印）"
echo "  ↑ 实时/终稿是两套白名单：realtime 走 streaming 型号，filetrans 走 filetrans 型号，勿混用"

CMD="${1:-run}"
case "$CMD" in
  run)
    exec "$FLUTTER" run "${DEFINES[@]}"
    ;;
  build)
    exec "$FLUTTER" build apk --debug "${DEFINES[@]}"
    ;;
  *)
    echo "用法：$0 [run|build]"
    exit 1
    ;;
esac
