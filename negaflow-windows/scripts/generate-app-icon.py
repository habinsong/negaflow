#!/usr/bin/env python3
"""투명 배경 원본 하나에서 Windows 앱 아이콘 자산을 만든다.

**알파를 잃지 않는 것이 이 스크립트의 존재 이유다.** macOS 는 자기 앱 아이콘용으로 일부러
불투명본(`AppIcon-App-1024.png`)을 만드는데(그것이 macOS 규칙이다), Windows 자산이 그
불투명본에서 나오는 바람에 앱 아이콘·정보 창·부팅 로고가 전부 검은 사각형 위에 얹혀 있었다.
Windows 는 투명 원본(`AppIcon-1024.png`)에서 나와야 한다.

**256 미만은 DIB 로 쓴다.** ICO 안의 PNG 는 256x256 에만 공식으로 허용되고, 그보다 작은
항목을 PNG 로 넣으면 Windows 작업 표시줄이 알파를 읽지 못해 아이콘 뒤가 **불투명한 흰색**
으로 나온다. Pillow 의 ICO 저장은 모든 크기를 PNG 로 쓰므로 컨테이너는 직접 조립한다 —
화소를 줄이는 일만 Pillow 에 맡긴다.

만드는 것:
    Assets/AppIcon-1024.png   32bpp RGBA 원본 사본
    Assets/Negaflow.ico       16·20·24·32·40·48·64·256
"""
from __future__ import annotations

import argparse
import io
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

# Windows 셸이 실제로 고르는 크기들이다. 큰 것 하나만 넣으면 작업 표시줄·탐색기가 스스로
# 줄이면서 가장자리가 뭉갠다.
SIZES = [16, 20, 24, 32, 40, 48, 64, 256]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=None)
    parser.add_argument("--assets", type=Path, default=None)
    arguments = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    repository_root = project_root.parent
    source = arguments.source or (
        repository_root / "negaflow-mac/Sources/negaflowApp/Resources/AppIcon-1024.png")
    assets = arguments.assets or (project_root / "src/Shell/Assets")

    if not source.is_file():
        print(f"원본 아이콘이 없다: {source}", file=sys.stderr)
        return 1

    with Image.open(source) as opened:
        if opened.mode != "RGBA":
            print(f"원본에 알파 채널이 없다({opened.mode}). 투명 원본을 줘야 한다: {source}",
                  file=sys.stderr)
            return 1
        if opened.getpixel((0, 0))[3] != 0:
            print("원본 모서리가 불투명하다. 불투명본을 원본으로 잘못 준 것이다.",
                  file=sys.stderr)
            return 1
        icon = opened.copy()

    assets.mkdir(parents=True, exist_ok=True)
    master = assets / "AppIcon-1024.png"
    shutil.copyfile(source, master)
    print(f"원본 사본: {master}")

    target = assets / "Negaflow.ico"
    target.write_bytes(build_icon(icon))

    problem = verify_icon(target)
    if problem is not None:
        print(problem, file=sys.stderr)
        return 1

    print(f"아이콘: {target} ({len(SIZES)} 크기, 256 만 PNG, 모서리 전부 투명)")
    return 0


def scaled(icon: Image.Image, size: int) -> Image.Image:
    return icon.resize((size, size), Image.LANCZOS)


def dib_entry(frame: Image.Image) -> bytes:
    """BITMAPINFOHEADER + 아래에서 위로 쌓은 BGRA + AND 마스크."""
    width, height = frame.size
    header = struct.pack(
        "<IiiHHIIiiII",
        40,                  # biSize
        width,
        height * 2,          # XOR 과 AND 를 합친 높이
        1,                   # biPlanes
        32,                  # biBitCount
        0,                   # BI_RGB
        width * height * 4,  # biSizeImage
        0, 0, 0, 0)
    pixels = frame.load()
    rows = bytearray()
    for y in range(height - 1, -1, -1):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            rows += bytes((blue, green, red, alpha))
    # 32bpp 아이콘에서도 AND 마스크 자리는 있어야 한다. 전부 0 이고, 실제 투명은 알파가 정한다.
    mask_stride = ((width + 31) // 32) * 4
    return header + bytes(rows) + bytes(mask_stride * height)


def build_icon(icon: Image.Image) -> bytes:
    entries: list[tuple[int, bytes]] = []
    for size in SIZES:
        frame = scaled(icon, size)
        if size >= 256:
            buffer = io.BytesIO()
            frame.save(buffer, format="PNG")
            entries.append((size, buffer.getvalue()))
        else:
            entries.append((size, dib_entry(frame)))

    directory = bytearray(struct.pack("<HHH", 0, 1, len(entries)))
    offset = 6 + 16 * len(entries)
    for size, payload in entries:
        directory += struct.pack(
            "<BBBBHHII",
            0 if size >= 256 else size,
            0 if size >= 256 else size,
            0,                 # 팔레트 없음
            0,                 # reserved
            1,                 # color planes
            32,                # bits per pixel
            len(payload),
            offset)
        offset += len(payload)
    return bytes(directory) + b"".join(payload for _, payload in entries)


def verify_icon(path: Path) -> str | None:
    """저장은 성공해도 조립이 틀릴 수 있다. 되읽어 확인한다."""
    raw = path.read_bytes()
    count = struct.unpack_from("<H", raw, 4)[0]
    if count != len(SIZES):
        return f"항목 수가 {count} 이다. {len(SIZES)} 여야 한다."
    for index, expected in enumerate(SIZES):
        base = 6 + index * 16
        width = raw[base] or 256
        length, offset = struct.unpack_from("<II", raw, base + 8)
        if width != expected:
            return f"{index} 번째 항목이 {width} 이다. {expected} 여야 한다."
        if offset + length > len(raw):
            return f"{expected}x{expected} 항목이 파일 밖을 가리킨다."
        head = raw[offset:offset + 8]
        if expected >= 256:
            if head[:2] != bytes((0x89, 0x50)):
                return "256x256 항목이 PNG 가 아니다."
            continue
        if struct.unpack_from("<I", head)[0] != 40:
            return f"{expected}x{expected} 항목의 DIB 머리글이 40 이 아니다."
        # 좌상단 화소의 알파. 행은 아래에서 위로 쌓았으므로 마지막 행의 첫 화소다.
        pixels_at = offset + 40
        top_row = pixels_at + (expected - 1) * expected * 4
        if raw[top_row + 3] != 0:
            return f"{expected}x{expected} 모서리가 불투명하다(A={raw[top_row + 3]})."
    return None


if __name__ == "__main__":
    raise SystemExit(main())
