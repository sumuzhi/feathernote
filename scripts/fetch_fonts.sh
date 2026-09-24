#!/usr/bin/env bash
# 拉取 UI 层使用的 Noto Sans SC 字体资源（离线可用，不依赖 google_fonts 运行时下载）。
#
# 设计规格要求全局字体为 Noto Sans SC，且禁止引入第三方组件库；
# 因此这里把 400/600 两个字重的完整字型作为 asset 打进 APK，
# 避免首屏因网络下载字体而出现字形回退（tofu）或闪烁。
#
# 若 assets/fonts 下已存在同名文件则跳过下载。

set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FONT_DIR="${ROOT_DIR}/assets/fonts"
readonly BASE_URL="https://fonts.gstatic.com/s/notosanssc"

# 版本号来自 Google Fonts CSS API 返回的 ucl0/ucl1 分片，修改前请确认链接仍有效。
declare -a FILES=(
  "NotoSansSC-Regular.ttf"
  "NotoSansSC-SemiBold.ttf"
)

mkdir -p "${FONT_DIR}"

for file in "${FILES[@]}"; do
  target="${FONT_DIR}/${file}"
  if [[ -s "${target}" ]]; then
    echo "skip  ${file} (already present)"
    continue
  fi
  echo "fetch ${file}"
  curl -fL --retry 3 --retry-delay 2 -o "${target}" "${BASE_URL}/${file}"
done

echo "done: ${FONT_DIR}"
ls -l "${FONT_DIR}"
