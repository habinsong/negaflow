#!/usr/bin/env python3
"""설치 프로그램이 쓰는 브랜딩 비트맵을 앱 아이콘에서 만든다.

NSIS 는 BMP 만 받고 알파를 읽지 않는다. 그래서 투명 아이콘을 각 화면의 실제 배경색 위에
합성해서 굽는다 — 그러지 않으면 아이콘 뒤에 검은 사각형이 남는다.

**두 배 크기로 굽는다.** 설치 마법사는 화면 배율을 따라 커지는데 비트맵은 그대로 그려져,
원래 크기로 구우면 아래·옆에 흰 여백이 남고 아이콘 가장자리가 뭉갠다. 크게 구워 놓고
`*_BITMAP_STRETCH` 로 칸에 맞춘다.

만드는 것:
    welcome.bmp  328x628  환영·완료 화면 왼쪽 판. 짙은 바탕에 아이콘과 워드마크.
    header.bmp   300x114  나머지 화면 머리글. 밝은 바탕에 아이콘만.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PANEL = (24, 24, 27)
ACCENT = (239, 139, 38)
WELCOME = (328, 628)
HEADER = (300, 114)


def load_wordmark(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    # Windows 10 부터 기본 탑재되는 기하학적 산세리프다. 따로 싣지 않고 시스템 것을 쓴다.
    for name in ("bahnschrift.ttf", "segoeuib.ttf", "arialbd.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    if not arguments.source.is_file():
        print(f"아이콘 원본이 없다: {arguments.source}", file=sys.stderr)
        return 1
    arguments.output.mkdir(parents=True, exist_ok=True)

    with Image.open(arguments.source) as opened:
        icon = opened.convert("RGBA")

    # ── 환영·완료 화면 왼쪽 판 ───────────────────────────────────────────────
    welcome = Image.new("RGB", WELCOME, PANEL)
    art = icon.resize((176, 176), Image.LANCZOS)
    welcome.paste(art, ((WELCOME[0] - 176) // 2, 156), art)
    draw = ImageDraw.Draw(welcome)
    font = load_wordmark(26)
    text = "NEGAFLOW"
    # 자간을 벌려 표지처럼 세운다. Pillow 에는 자간이 없으므로 글자를 하나씩 놓는다.
    spacing = 6
    widths = [draw.textlength(letter, font=font) for letter in text]
    total = sum(widths) + spacing * (len(text) - 1)
    cursor = (WELCOME[0] - total) / 2
    for letter, width in zip(text, widths):
        draw.text((cursor, 364), letter, font=font, fill=(255, 255, 255))
        cursor += width + spacing
    # 워드마크 아래 가느다란 강조선 하나. 장식은 이것뿐이다.
    draw.rectangle([(WELCOME[0] - 56) // 2, 424, (WELCOME[0] + 56) // 2, 427], fill=ACCENT)
    welcome.save(arguments.output / "welcome.bmp", format="BMP")

    # ── 머리글 ──────────────────────────────────────────────────────────────
    # 마법사 머리글은 시스템이 흰색으로 칠한다. 같은 흰색 위에 아이콘만 얹는다.
    header = Image.new("RGB", HEADER, (255, 255, 255))
    mark = icon.resize((80, 80), Image.LANCZOS)
    header.paste(mark, (HEADER[0] - 80 - 24, (HEADER[1] - 80) // 2), mark)
    header.save(arguments.output / "header.bmp", format="BMP")

    print(f"브랜딩 비트맵: {arguments.output} (welcome.bmp, header.bmp)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
