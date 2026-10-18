#!/usr/bin/env bash
# 交叉编译 keytriggerd（aarch64 Android，静态 PIE，无运行时依赖）。
set -euo pipefail
cd "$(dirname "$0")"

NDK="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/29.0.14206865}"
CLANG="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang"

if [[ ! -x "$CLANG" ]]; then
  echo "找不到 NDK clang：$CLANG" >&2
  echo "请设置 ANDROID_NDK_HOME 指向 NDK 根目录" >&2
  exit 1
fi

mkdir -p module
"$CLANG" -O2 -Wall -Wextra -Werror -fPIE -pie \
  -o module/keytriggerd src/keytriggerd.c

echo "构建完成：module/keytriggerd"
file module/keytriggerd
