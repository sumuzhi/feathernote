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
#   4. 由模板重新生成 apk-share/version.json 与 index.html
#      （版本/构建戳/MD5/下载链接/更新说明全部变量化）；
#   5. git push origin main。
#
# ⚠️ 最后一步（CDN 部署）需要 WorkBuddy 对话内的 sites 通道：
#    脚本跑完后回到对话说「部署」即可完成上传与线上核验。
#
# 可移植性说明：脚本在 macOS BSD 工具链与 toybox 等非 GNU 环境都能跑——
# 不用 `sed -i`（BSD/GNU/toybox 三方语义不同，实测 toybox 会把 `''` 当空脚本），
# 文件改写走 awk 输出重定向；MD5 做 md5sum/md5 双兼容。
#
# 环境要求：项目根有 .env（含 DASHSCOPE_API_KEY）；JAVA_HOME / FLUTTER /
# ANDROID_SDK_ROOT 可用环境变量覆盖（默认与日常构建一致）。
set -euo pipefail

VERSION="${1:?用法: $0 <版本号，如 1.0.13> [更新说明]}"
NOTES="${2:-详见下载页更新说明。}"

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-$HOME/.workbuddy/binaries/flutter/flutter/bin/flutter}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.workbuddy/binaries/java/jdk-21.0.2.jdk/Contents/Home}"
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
if [[ "$VERSION_CODE" -lt "$CURRENT_CODE" ]]; then
  echo "❌ versionCode(${VERSION_CODE}) 不能小于当前(${CURRENT_CODE})——设备会判定降级"
  exit 1
fi
if [[ "$VERSION_CODE" -eq "$CURRENT_CODE" ]]; then
  echo "ℹ️ versionCode(${VERSION_CODE}) 与当前相同——视为中断续跑"
fi
echo "✅ 目标版本 ${VERSION}+${VERSION_CODE}（当前 versionCode=${CURRENT_CODE}）"

# ── 1. bump 版本并提交 ─────────────────────────────────────────────────────────
step "1/6 bump 版本并提交"
if [[ "$CURRENT_CODE" -ge "$VERSION_CODE" ]]; then
  # 幂等：上次发布中断在 bump 之后时，直接续跑（不重复提交）。
  echo "✅ 已处于目标版本 ${VERSION}+${VERSION_CODE}，跳过 bump（沿用中断的发布）"
else
  awk -v ver="${VERSION}+${VERSION_CODE}" \
    '{ if ($0 ~ /^version: /) print "version: " ver; else print }' \
    pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
  grep '^version:' pubspec.yaml
  git add pubspec.yaml
  git commit -m "chore(release): bump ${VERSION}+${VERSION_CODE}"
  echo "✅ 已提交 bump"
fi
HASH=$(git rev-parse --short HEAD)
echo "✅ 提交 ${HASH}"

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

STAMP="$(date +%m%d-%H%M)/${HASH}"
STAMP_FILE="${STAMP/\//-}"   # 文件名里的戳不带斜杠
BUILD_TIME="$(date '+%Y-%m-%d %H:%M')"
"$FLUTTER" build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define=DASHSCOPE_API_KEY="${DASHSCOPE_API_KEY}" \
  --dart-define=DASHSCOPE_WORKSPACE_ID="${DASHSCOPE_WORKSPACE_ID:-}" \
  --dart-define=BAILIAN_REGION="${BAILIAN_REGION:-cn-beijing}" \
  --dart-define=BAILIAN_REALTIME_MODEL="qwen-audio-3.0-asr-flash-streaming" \
  --dart-define=BAILIAN_FILETRANS_MODEL="${BAILIAN_FILETRANS_MODEL:-qwen-audio-3.1-asr-flash-filetrans}" \
  --dart-define=BAILIAN_LLM_MODEL="${BAILIAN_LLM_MODEL:-qwen3.7-plus}" \
  --dart-define=ENGINE_PROVIDER="${ENGINE_PROVIDER:-bailian}" \
  --dart-define=LOG_LEVEL="${LOG_LEVEL:-debug}" \
  --dart-define=SMART_MINUTES_VERSION="${VERSION}" \
  --dart-define=BUILD_STAMP="${STAMP}" 2>&1 | tail -3
echo "✅ 构建完成 STAMP=${STAMP}"

# ── 3. APK 落位 + MD5（md5sum/md5 双兼容）────────────────────────────────────
step "3/6 APK 落位 apk-share/"
APK_SRC="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
APK_NAME="feathernote-release-${STAMP_FILE}-arm64.apk"
[[ -f "$APK_SRC" ]] || { echo "❌ 构建产物缺失：$APK_SRC"; exit 1; }
rm -f apk-share/feathernote-release-*-arm64.apk
cp "$APK_SRC" "apk-share/$APK_NAME"
if command -v md5sum >/dev/null 2>&1; then
  MD5=$(md5sum "apk-share/$APK_NAME" | cut -d' ' -f1)
else
  MD5=$(md5 -q "apk-share/$APK_NAME")
fi
MD5_SHORT="${MD5:0:8}…${MD5: -5}"
echo "✅ $APK_NAME  MD5=$MD5"

# ── 4. 由模板重新生成 version.json / index.html ───────────────────────────────
step "4/6 生成 version.json / index.html"
# HTML 转义更新说明（& < >）。
NOTES_HTML=$(printf '%s' "$NOTES" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

cat > apk-share/version.json << EOF
{
  "version": "${VERSION}",
  "versionCode": ${VERSION_CODE},
  "buildStamp": "${STAMP}",
  "minVersionCode": 1,
  "downloadUrl": "https://2d1c7d182ab842d9adc9e83f7f76e75f.app.workbuddy.host/${APK_NAME}",
  "releaseNotes": "${NOTES_HTML}",
  "forceUpdate": false
}
EOF

cat > apk-share/index.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta http-equiv="Cache-Control" content="no-store, no-cache, must-revalidate" />
  <title>声羽 FeatherNote 安装包</title>
  <style>
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
      background: #FAF3EC;
      color: #2b2b2b;
      display: flex;
      justify-content: center;
      padding: 28px 18px 40px;
    }
    .card {
      width: 100%;
      max-width: 420px;
      background: #fff;
      border-radius: 20px;
      box-shadow: 0 10px 30px rgba(240,120,60,0.12);
      padding: 28px 22px 26px;
      text-align: center;
    }
    .badge {
      display: inline-block;
      background: #FBE9DB;
      color: #F0783C;
      font-size: 13px;
      font-weight: 600;
      padding: 6px 12px;
      border-radius: 999px;
      margin-bottom: 14px;
    }
    h1 { font-size: 21px; margin: 6px 0 4px; }
    .sub { color: #8a8a8a; font-size: 14px; margin: 0 0 22px; }
    .dl {
      display: inline-block;
      width: 100%;
      text-decoration: none;
      background: #F0783C;
      color: #fff;
      font-size: 17px;
      font-weight: 600;
      padding: 15px 18px;
      border-radius: 14px;
      transition: opacity .15s ease;
    }
    .dl:active { opacity: .85; }
    .arch {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      margin: 8px 2px 6px;
      font-size: 13px;
      color: #8a8a8a;
    }
    .arch b { color: #2b2b2b; font-size: 14px; }
    .meta { font-size: 13px; color: #8a8a8a; margin: 6px 0 0; }
    .note {
      margin-top: 22px;
      text-align: left;
      background: #FFF0E3;
      border-radius: 12px;
      padding: 14px 16px;
      font-size: 13px;
      line-height: 1.7;
      color: #7a5a44;
    }
    .note b { color: #F0783C; }
    .ver {
      margin-top: 20px;
      text-align: left;
      background: #F7F4F0;
      border-radius: 12px;
      padding: 13px 16px;
      font-size: 12.5px;
      line-height: 1.8;
      color: #6b6b6b;
    }
    .ver b { color: #2b2b2b; font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12px; }
    .ver .t { font-size: 13px; font-weight: 700; color: #2b2b2b; margin-bottom: 4px; }
    .updated { color: #2e9e5b; font-weight: 700; }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge">声羽 FeatherNote · 会议纪要</span>
    <h1>声羽 FeatherNote 安卓安装包</h1>
    <p class="sub">⚠️ 已更名并更换包名：安装前请先卸载旧版 App</p>

    <div class="arch"><b>Release 版（arm64 · 推荐）</b><span>约 30 MB</span></div>
    <a class="dl" href="${APK_NAME}" download>⬇ 下载 Release 版 APK</a>
    <p class="meta">arm64-v8a 单架构 · AOT 编译 · 体积小 · 与既有安装同形态可直接覆盖</p>

    <div class="note">
      <b>安装前请先授权：</b><br />
      安卓系统默认禁止未知来源安装。下载后点击安装，若提示「已阻止安装」，
      请前往 <b>设置 → 安全 → 安装未知应用</b>，允许你当前使用的浏览器，再返回继续安装。
    </div>

    <div class="ver">
      <div class="t">版本信息 <span class="updated">● 最新构建已发布</span></div>
      构建时间：<b>${BUILD_TIME}</b><br />
      构建戳：<b>${STAMP}</b><br />
      Release 大小 / MD5：<b>30.2 MB</b> / <b>${MD5_SHORT}</b>
      <br /><br />
      📱 <b>核对方法</b>：安装后打开 App 的「设置」页，最底部版本行会显示
      <b>${STAMP}</b> —— 与这里一致，说明你手机上就是最新版。
      <br />✦ <b>本版更新（${VERSION}）</b>：${NOTES_HTML}
    </div>
  </div>
</body>
</html>
EOF

# JSON 合法性自检（python3 为 macOS 自带）。
python3 -c "import json;json.load(open('apk-share/version.json'))" \
  || { echo "❌ version.json 不是合法 JSON"; exit 1; }
echo "✅ version.json / index.html 已重新生成"

# ── 5. push ────────────────────────────────────────────────────────────────────
step "5/6 git push"
git push origin main
echo "✅ 已推送（HEAD=$(git rev-parse --short HEAD)）"

# ── 6. 完成 ────────────────────────────────────────────────────────────────────
step "6/6 发布物就绪"
cat << EOF

✅ ${VERSION}(${VERSION_CODE}) 构建与发布物准备完毕：
   APK   = apk-share/$APK_NAME
   MD5   = $MD5
   STAMP = $STAMP

⚠️ 最后一步：回到 WorkBuddy 对话说「部署」，由主理人完成 CDN 上传与
   线上核验（manifest / APK / 更新通道判定）。设备更新提示在 CDN
   上线后即生效。
EOF
