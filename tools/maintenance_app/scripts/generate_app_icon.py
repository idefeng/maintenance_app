#!/usr/bin/env python3
"""生成 MaintenanceApp 的 macOS 图标素材。"""

from __future__ import annotations

import subprocess
from pathlib import Path

TOOL_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PNG = TOOL_ROOT / "Resources" / "AppBundle" / "app_icon_source.png"
ICONSET_ROOT = TOOL_ROOT / ".build" / "generated" / "MaintenanceApp.iconset"
ICNS_PATH = TOOL_ROOT / ".build" / "generated" / "MaintenanceApp.icns"

ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

def main() -> int:
    """使用 macOS 原生 sips 缩放生成 iconset，并转换为 icns。"""
    if not SOURCE_PNG.exists():
        print(f"找不到来源图标：{SOURCE_PNG}")
        return 1

    if ICONSET_ROOT.exists():
        import shutil
        shutil.rmtree(ICONSET_ROOT)
    ICONSET_ROOT.mkdir(parents=True, exist_ok=True)
    
    for filename, size in ICON_SIZES.items():
        dest_path = ICONSET_ROOT / filename
        # 调用 macOS 原生的 sips 系统工具进行极速无损缩放
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(SOURCE_PNG), "--out", str(dest_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True
        )

    # 打包为 macOS 系统标准的 icns 图标包
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET_ROOT), "-o", str(ICNS_PATH)], check=True)
    print(f"成功生成并打包 macOS 图标：{ICNS_PATH}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
