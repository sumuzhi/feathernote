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

FLUTTER="${FLUTTER_BIN:-/Users/sumuzhi/.workbuddy/binaries/flutter/flutter/bin/flutter}"

DEFINES=(
  "--dart-define=DASHSCOPE_API_KEY=$DASHSCOPE_API_KEY"
  "--dart-define=DASHSCOPE_WORKSPACE_ID=${DASHSCOPE_WORKSPACE_ID:-}"
  "--dart-define=BAILIAN_REGION=${BAILIAN_REGION:-cn-beijing}"
  # 注意：Flutter 侧默认值是 3.0，这里显式用 3.1 与原 Node 项目保持一致
  "--dart-define=BAILIAN_REALTIME_MODEL=${BAILIAN_REALTIME_MODEL:-qwen-audio-3.1-asr-flash-streaming}"
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
echo "  realtime      = ${BAILIAN_REALTIME_MODEL:-qwen-audio-3.1-asr-flash-streaming}"
echo "  filetrans     = ${BAILIAN_FILETRANS_MODEL:-qwen-audio-3.1-asr-flash-filetrans}"
echo "  llm           = ${BAILIAN_LLM_MODEL:-qwen3.7-plus}"
echo "  log level     = ${LOG_LEVEL:-debug}"
echo "  api key 长度  = ${#DASHSCOPE_API_KEY}（值不打印）"

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
