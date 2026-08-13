"""Shell.Core / Interop 에 있는데 셸이 한 번도 이름을 부르지 않는 공개 타입을 찾습니다.

이번 프로젝트에서 가장 자주 나온 결함 모양이 "엔진에는 있는데 UI 가 없어서 아무도 쓸 수 없는
기능"입니다(프리셋, 색상 다섯 축, 흑백 토닝, 자동 GrainMend 세기, 스캐너, 소프트 프루프).
새 기능을 만들기 전에 이걸 먼저 돌리십시오 — 이미 만들어 둔 것을 여는 편이 훨씬 쌉니다.

    py scripts/find-unreachable-api.py

**출력은 손으로 걸러야 합니다.** 셸이 직접 이름을 부르지 않아도 Shell.Core 안에서 이어져
도달하는 배관 타입이 많습니다(예: DevelopExportRequest 는 DevelopRequestFactory 가 만들어
넘깁니다). 진짜 후보는 "그 타입을 쓰는 사슬 전체가 셸에서 시작되지 않는" 것들입니다.
"""

import os
import re
import sys

# 콘솔 코드 페이지가 CP949 라도 한국어 설명이 깨지지 않게 합니다.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOTS = ("src/Shell.Core", "src/Interop")
SHELL = "src/Shell"
DECLARATION = re.compile(
    r"^public (?:static |sealed |abstract |readonly |partial )*"
    r"(?:class|record|struct|interface|enum)\s+(\w+)",
    re.M,
)


def public_types() -> dict[str, str]:
    found: dict[str, str] = {}
    for root in ROOTS:
        for directory, _, files in os.walk(root):
            if os.sep + "obj" + os.sep in directory:
                continue
            for name in files:
                if not name.endswith(".cs"):
                    continue
                path = os.path.join(directory, name)
                with open(path, encoding="utf-8") as handle:
                    for match in DECLARATION.finditer(handle.read()):
                        found.setdefault(match.group(1), path)
    return found


def shell_text() -> str:
    parts = []
    for directory, _, files in os.walk(SHELL):
        if os.sep + "obj" + os.sep in directory:
            continue
        for name in files:
            if name.endswith((".cs", ".xaml")):
                with open(os.path.join(directory, name), encoding="utf-8",
                          errors="ignore") as handle:
                    parts.append(handle.read())
    return "\n".join(parts)


def main() -> None:
    types = public_types()
    blob = shell_text()
    unused = sorted(
        name for name in types
        if not re.search(r"\b" + re.escape(name) + r"\b", blob))
    print(f"public types: {len(types)}, never named in {SHELL}: {len(unused)}")
    print("(배관 타입이 섞여 있습니다 — 사슬을 따라가 직접 확인하십시오)\n")
    for name in unused:
        print(f"  {name}  <- {types[name]}")


if __name__ == "__main__":
    main()
