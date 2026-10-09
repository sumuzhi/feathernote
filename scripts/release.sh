#!/usr/bin/env bash
# 一键发布脚本：bump 版本 → 构建 arm64 Release APK → 准备 apk-share 发布物 → push。
#
# 用法：
#   ./scripts/release.sh <版本号> ["更新说明"]
#   例：./scripts/release.sh 1.0.13 "备份按每场会议单独导出 md"
#
# 做了什么（与人工流水线一致）：
#   1. bump pubspec 版本（versionCode = 末段补丁号 + 1，强制单调递增）并提交；
#   2. 临时 gradle.properties daemon=false → 构建 arm64-v8a split Release APK
#      （注入 DASHSCOPE key / 模型 / BUILD_STAMP，与 run_real.sh 同源）；
#   3. APK 落位 apk-share/（清理旧包），计算 MD5；
#   4. 更新 apk-share/version.json（version/versionCode/buildStamp/downloadUrl/releaseNotes）
#      与 index.html（下载链接 / 构建时间 / 构建戳 / MD5 / 核对行）；
#   5. git push origin main。
#
# ⚠️ 最后一步（CDN 部署）需要 WorkBuddy 对话内的 sites 通道：
#    脚本跑完后回到对话说「部署」即可完成上传与线上核验。
#
# 环境要求：项目根有 .env（含 DASHSCOPE_API_KEY）；JAVA_HOME / FLUTTER /
# ANDROID_SDK_ROOT 可用环境变量覆盖（默认与日常构建一致）。
set -euo pipefail

VERSION="${1:?用法: $0 <版本号，如 1.0.13> [更新说明]}"
NOTES="${2:-}"

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-$HOME/workbuddy/binaries/flutter/flutter/bin/flutter}"
export JAVA_HOME="${JAVA_HOME:-$HOME/workbuddy/binaries/java/jdk-21.0.2.jdk/Contents/Home}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
export PATH="$JAVA_HOME/bin:$FLUTTER/bin:$PATH"

step() { echo ""; echo "━━━ $1 ━━━"; }

# ── 0. 前置检查 ────────────────────────────────────────────────────────────────
step "0/6 前置检查"
[[ -f .env ]] || { echo "❌ 缺少 .env（含 DASHSCOPE_API_KEY）"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "❌ 工作区有未提交改动，请先提交/暂存"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ 版本号格式应为 x.y.z：$VERSION"; exit 1; }

PATCH="${VERSION##*.}"
VERSION_CODE=$((PATCH + 1))
CURRENT_CODE=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
if [[ "$VERSION_CODE" -le "$CURRENT_CODE" ]]; then
  echo "❌ versionCode($VERSION_CODE) 必须大于当前($CURRENT_CODE)——否则设备会判定降级"
  exit 1
fi
echo "✅ 目标版本 $VERSION+$VERSION_CODE（当前 versionCode=$CURRENT_CODE）"

# ── 1. bump 版本并提交 ─────────────────────────────────────────────────────────
step "1/6 bump 版本并提交"
sed -i '' "s/^version: .*/version: $VERSION+$VERSION_CODE/" pubspec.yaml
git add pubspec.yaml
git commit -m "chore(release): bump $VERSION+$VERSION_CODE"
HASH=$(git rev-parse --short HEAD)
echo "✅ 提交 $HASH"

# ── 2. 构建 arm64-v8a split Release APK ───────────────────────────────────────
step "2/6 构建 Release APK（arm64-v8a 单架构）"
# 临时关闭 Gradle daemon（沙箱上下文残留问题），脚本退出时自动恢复。
echo "org.gradle.daemon=false" >> android/gradle.properties
restore_gradle() { git checkout -- android/gradle.properties; }
trap restore_gradle EXIT

set -a
# shellcheck disable=SC1091
. ./.env
set +a
[[ "${DASHSCOPE_API_KEY:-}" == sk-* ]] || { echo "❌ DASHSCOPE_API_KEY 非法（未以 sk- 开头）"; exit 1; }

STAMP="$(date +%m%d-%H%M)/$HASH"
STAMP_FILE="${STAMP/\//-}"   # 文件名里的戳不带斜杠
BUILD_TIME="$(date '+%Y-%m-%d %H:%M')"
"$FLUTTER" build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define=DASHSCOPE_API_KEY="$DASHSCOPE_API_KEY" \
  --dart-define=DASHSCOPE_WORKSPACE_ID="${DASHSCOPE_WORKSPACE_ID:-}" \
  --dart-define=BAILIAN_REGION="${BAILIAN_REGION:-cn-beijing}" \
  --dart-define=BAILIAN_REALTIME_MODEL="qwen-audio-3.0-asr-flash-streaming" \
  --dart-define=BAILIAN_FILETRANS_MODEL="${BAILIAN_FILETRANS_MODEL:-qwen-audio-3.1-asr-flash-filetrans}" \
  --dart-define=BAILIAN_LLM_MODEL="${BAILIAN_LLM_MODEL:-qwen3.7-plus}" \
  --dart-define=ENGINE_PROVIDER="${ENGINE_PROVIDER:-bailian}" \
  --dart-define=LOG_LEVEL="${LOG_LEVEL:-debug}" \
  --dart-define=SMART_MINUTES_VERSION="$VERSION" \
  --dart-define=BUILD_STAMP="$STAMP" 2>&1 | tail -3
echo "✅ 构建完成 STAMP=$STAMP"

# ── 3. APK 落位 + MD5 ──────────────────────────────────────────────────────────
step "3/6 APK 落位 apk-share/"
APK_SRC="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
APK_NAME="feathernote-release-$STAMP_FILE-arm64.apk"
[[ -f "$APK_SRC" ]] || { echo "❌ 构建产物缺失：$APK_SRC"; exit 1; }
rm -f apk-share/feathernote-release-*-arm64.apk
cp "$APK_SRC" "apk-share/$APK_NAME"
MD5=$(md5 -q "apk-share/$APK_NAME")
MD5_SHORT="${MD5:0:8}…${MD5: -5}"
echo "✅ $APK_NAME  MD5=$MD5"

# ── 4. 更新 version.json / index.html ─────────────────────────────────────────
step "4/6 更新 version.json / index.html"
if [[ -z "$NOTES" ]]; then
  NOTES="详见下载页更新说明。"
fi
# JSON 转义：反斜杠与双引号。
NOTES_JSON=$(printf '%s' "$NOTES" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

cat > apk-share/version.json << EOF
{
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "buildStamp": "$STAMP",
  "minVersionCode": 1,
  "downloadUrl": "https://2d1c7d182ab842d9adc9e83f7f76e75f.app.workbuddy.host/$APK_NAME",
  "releaseNotes": "$NOTES_JSON",
  "forceUpdate": false
}
EOF

sed -i '' \
  -e "s|feathernote-release-[0-9]*-[0-9]*-arm64\.apk|$APK_NAME|" \
  -e "s|构建时间：<b>[^<]*</b>|构建时间：<b>$BUILD_TIME</b>|" \
  -e "s|构建戳：<b>[^<]*</b>|构建戳：<b>$STAMP</b>|" \
  -e "s|Release 大小 / MD5：<b>[^<]*</b> / <b>[^<]*</b>|Release 大小 / MD5：<b>30.2 MB</b> / <b>$MD5_SHORT</b>|" \
  -e "s|<b>[0-9]*-[0-9]*\/[0-9a-f]*</b> —— 与这里一致|<b>$STAMP</b> —— 与这里一致|" \
  apk-share/index.html

if [[ -n "$NOTES" ]]; then
  sed -i '' "s|<br />✦ <b>本版更新.*$|<br />✦ <b>本版更新（$VERSION）</b>：$NOTES|" apk-share/index.html
fi

# JSON 合法性自检（python3 为 macOS 自带）。
python3 -c "import json;json.load(open('apk-share/version.json'))" \
  || { echo "❌ version.json 不是合法 JSON"; exit 1; }
echo "✅ version.json / index.html 已更新"

# ── 5. push ────────────────────────────────────────────────────────────────────
step "5/6 git push"
git push origin main
echo "✅ 已推送（HEAD=$(git rev-parse --short HEAD)）"

# ── 6. 完成 ────────────────────────────────────────────────────────────────────
step "6/6 发布物就绪"
cat << EOF

✅ $VERSION($VERSION_CODE) 构建与发布物准备完毕：
   APK   = apk-share/$APK_NAME
   MD5   = $MD5
   STAMP = $STAMP

⚠️ 最后一步：回到 WorkBuddy 对话说「部署」，由主理人完成 CDN 上传与
   线上核验（manifest / APK / 更新通道判定）。设备更新提示在 CDN
   上线后即生效。
EOF
