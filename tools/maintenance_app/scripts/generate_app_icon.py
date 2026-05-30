#!/usr/bin/env python3
"""生成 MaintenanceApp 的 macOS 图标素材。"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import zlib
from pathlib import Path


TOOL_ROOT = Path(__file__).resolve().parents[1]
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


def png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    """生成单个 PNG chunk。"""
    checksum = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", checksum)


def write_png(path: Path, width: int, height: int, rgba_rows: list[bytes]) -> None:
    """写入 RGBA PNG 文件。"""
    raw = b"".join(b"\x00" + row for row in rgba_rows)
    payload = [
        b"\x89PNG\r\n\x1a\n",
        png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
        png_chunk(b"IDAT", zlib.compress(raw, 9)),
        png_chunk(b"IEND", b""),
    ]
    path.write_bytes(b"".join(payload))


def rounded_rect_mask(x: float, y: float, size: int, radius: float) -> float:
    """计算圆角矩形边缘的抗锯齿透明度。"""
    inset = size * 0.055
    left = inset
    top = inset
    right = size - inset
    bottom = size - inset
    nearest_x = min(max(x, left + radius), right - radius)
    nearest_y = min(max(y, top + radius), bottom - radius)
    distance = math.hypot(x - nearest_x, y - nearest_y)
    return max(0.0, min(1.0, radius + 1.0 - distance))


def blend(top: tuple[int, int, int, int], bottom: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """按 alpha 混合两个颜色。"""
    alpha = top[3] / 255.0
    inverse = 1.0 - alpha
    return (
        round(top[0] * alpha + bottom[0] * inverse),
        round(top[1] * alpha + bottom[1] * inverse),
        round(top[2] * alpha + bottom[2] * inverse),
        round(255 * (alpha + bottom[3] / 255.0 * inverse)),
    )


def draw_icon(size: int) -> list[bytes]:
    """绘制简洁的本机维护图标。"""
    rows: list[bytes] = []
    center = size / 2
    radius = size * 0.22
    ring_outer = size * 0.23
    ring_inner = size * 0.165
    mark_width = max(1.0, size * 0.035)

    for y in range(size):
        row = bytearray()
        for x in range(size):
            px = x + 0.5
            py = y + 0.5
            mask = rounded_rect_mask(px, py, size, size * 0.205)
            if mask <= 0:
                row.extend((0, 0, 0, 0))
                continue

            vertical = py / size
            base = (
                round(28 + 42 * (1 - vertical)),
                round(111 + 68 * (1 - vertical)),
                round(155 + 54 * (1 - vertical)),
                round(255 * mask),
            )

            # 左上角高光，提升 Dock 小尺寸下的层次。
            highlight_distance = math.hypot(px - size * 0.28, py - size * 0.22)
            if highlight_distance < size * 0.36:
                strength = (1 - highlight_distance / (size * 0.36)) * 0.24
                base = blend((255, 255, 255, round(255 * strength)), base)

            dx = px - center
            dy = py - center
            distance = math.hypot(dx, dy)
            gear = False
            for tooth in range(12):
                angle = tooth * math.pi / 6
                projection = abs(dx * math.cos(angle) + dy * math.sin(angle))
                tangent = abs(-dx * math.sin(angle) + dy * math.cos(angle))
                if ring_outer < projection < ring_outer + size * 0.095 and tangent < size * 0.026:
                    gear = True
                    break

            if ring_inner < distance < ring_outer or gear:
                base = blend((245, 252, 255, 235), base)

            if distance < radius * 0.47:
                base = blend((24, 68, 90, 255), base)

            # 勾形表示“已检查/维护完成”，避免只像普通齿轮工具。
            first_segment = abs((py - (center + size * 0.08)) - 0.95 * (px - (center - size * 0.18))) < mark_width
            second_segment = abs((py - (center + size * 0.09)) + 0.58 * (px - (center + size * 0.05))) < mark_width
            in_first = first_segment and center - size * 0.22 < px < center - size * 0.01
            in_second = second_segment and center - size * 0.02 < px < center + size * 0.28
            if in_first or in_second:
                base = blend((88, 226, 153, 255), base)

            row.extend(base)
        rows.append(bytes(row))
    return rows


def main() -> int:
    """生成 iconset 并转换为 icns。"""
    ICONSET_ROOT.mkdir(parents=True, exist_ok=True)
    for filename, size in ICON_SIZES.items():
        write_png(ICONSET_ROOT / filename, size, size, draw_icon(size))

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET_ROOT), "-o", str(ICNS_PATH)], check=True)
    print(ICNS_PATH)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
