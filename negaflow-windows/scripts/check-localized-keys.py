"""AppResources.Get(...) 로 부르는 키가 여섯 언어 resw 에 모두 있는지 봅니다.

없는 키는 실행 중에 InvalidOperationException 을 던져 설정 창을 죽입니다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRINGS = ROOT / "src/Shell/Strings"
LANGS = ["en-US", "ko-KR", "ja-JP", "zh-Hans", "fr-FR", "de-DE"]

CALL = re.compile(r'AppResources\.Get\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)')
FORMAT = re.compile(r'AppResources\.Format\w*\(\s*"([^"]+)"\s*,\s*"([^"]+)"')
DATA = re.compile(r'<data name="([^"]+)"')


def main():
    available = {}
    for lang in LANGS:
        text = (STRINGS / lang / "Resources.resw").read_text(encoding="utf-8")
        available[lang] = set(DATA.findall(text))

    wanted = set()
    for path in ROOT.joinpath("src/Shell").rglob("*.cs"):
        text = path.read_text(encoding="utf-8")
        for key, prop in CALL.findall(text) + FORMAT.findall(text):
            wanted.add((f"{key}.{prop}", str(path.relative_to(ROOT))))

    missing = []
    for name, where in sorted(wanted):
        gaps = [lang for lang in LANGS if name not in available[lang]]
        if gaps:
            missing.append((name, where, gaps))
    for name, where, gaps in missing:
        print(f"MISSING {name}  ({where})  -> {', '.join(gaps)}")
    print(f"\nchecked {len(wanted)} keys, {len(missing)} missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
