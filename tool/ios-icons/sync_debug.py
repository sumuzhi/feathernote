#!/usr/bin/env python3
"""同步 iOS Debug 图标集（AppIcon-ios-debug）。

用法（在仓库根目录）：
  /path/to/python tool/ios-icons/sync_debug.py

依赖：Pillow。源图 tool/ios-icons/icon-debug-1024.png（深棕底 #221A14 + 白色羽翼，
由 assets/brand/icon-fg-1024.png 叠加合成——见仓库根 flutter_launcher_icons-ios.yaml 注释）。

背景：flutter_launcher_icons 只能从单一 image_path 生成一套 appiconset；
Debug/Release 双色区分靠本脚本把 Release 集（AppIcon-ios，由
`dart run flutter_launcher_icons -f flutter_launcher_icons-ios.yaml` 生成）
复制为 AppIcon-ios-debug 并按同名尺寸重绘。Debug.xcconfig 将
ASSETCATALOG_COMPILER_APPICON_NAME 指向 AppIcon-ios-debug，Release.xcconfig 指向 AppIcon-ios。
"""
from __future__ import annotations

import os
import re
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_DIR = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon-ios.appiconset")
DST_DIR = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon-ios-debug.appiconset")
DEBUG_1024 = os.path.join(ROOT, "tool", "ios-icons", "icon-debug-1024.png")

# AppIcon-ios-60x60@2x.png → ('60x60', '2')
NAME = re.compile(r"AppIcon-ios-(.+)@(\d)x\.png$")


def main() -> None:
    shutil.copytree(SRC_DIR, DST_DIR, dirs_exist_ok=True)
    base = Image.open(DEBUG_1024).convert("RGB")
    for name in sorted(os.listdir(DST_DIR)):
        if not name.endswith(".png"):
            continue
        m = NAME.match(name)
        if not m:
            raise SystemExit(f"无法解析图标文件名：{name}")
        w, h = (float(v) for v in m.group(1).split("x"))
        mult = int(m.group(2))
        target = (round(w * mult), round(h * mult))
        base.resize(target, Image.LANCZOS).save(os.path.join(DST_DIR, name))
        print(f"{name} -> {target[0]}x{target[1]}")
    print(f"完成：{DST_DIR}")


if __name__ == "__main__":
    main()
