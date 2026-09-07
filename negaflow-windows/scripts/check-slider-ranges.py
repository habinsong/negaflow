"""XAML 의 모든 `Slider` 가 WinUI 가 받아들이는 범위를 갖는지 봅니다.

`StepFrequency="0"` 은 빌드를 통과하고 **손잡이를 잡는 순간** 창을 통째로 내립니다.
WinUI Slider 는 값을 이 간격으로 스냅하므로 0 이면 나눗셈이 NaN 이 되고,
그 NaN 이 배치로 들어가 아래 예외가 납니다.

    System.ArgumentException: The value cannot be infinite or Not a Number (NaN).

실제로 2026-09-03 에 GrainMend 브러시 두께 슬라이더가 이것으로 죽었습니다. 슬라이더
하나하나를 손으로 만져 보지 않으면 드러나지 않는 자리라, 여기서 한 번에 봅니다.

`Minimum > Maximum` 과 `StepFrequency` 가 범위보다 큰 것도 함께 막습니다 — 둘 다
움직이지 않는 슬라이더를 만듭니다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ROOT / "src/Shell"

# `<Slider ... />` 또는 `<Slider ... >` 한 덩이. 여는 태그만 봅니다.
SLIDER = re.compile(r"<Slider\b(.*?)(?:/>|>)", re.DOTALL)
ATTRIBUTE = re.compile(r'(\w[\w.:]*)\s*=\s*"([^"]*)"')

# `RangeBase.Maximum` 의 기본값. XAML 은 속성을 적힌 차례대로 넣으므로, `Maximum` 보다
# 먼저 적힌 `Minimum` 은 이 값과 견줍니다.
DEFAULT_MAXIMUM = 1.0


def number(value):
    try:
        return float(value)
    except ValueError:
        return None


def describe(attributes):
    name = attributes.get("x:Name")
    if name:
        return name
    return attributes.get("AutomationProperties.AutomationId", "<unnamed>")


# macOS 가 정한 값과 어긋나면 안 되는 슬라이더입니다.
#
# `x:Name` -> (스위프트 파일, 범위 상수 무늬, 스텝 상수 무늬)
#
# **맥 소스에서 직접 읽습니다.** 여기에 숫자를 베껴 두면 맥이 바뀌었을 때 아무도 모릅니다 -
# 두 쪽이 조용히 갈라지는 것이 정확히 이 규칙이 막으려는 것입니다.
MAC_BOUND_SLIDERS = {
    "GammaSlider": (
        "Sources/Chromabase/Develop/InputGammaInterpretation.swift",
        r"static let range\s*=\s*([0-9.]+)\s*\.\.\.\s*([0-9.]+)",
        "Sources/negaflowApp/Features/Develop/Inspector/Controls/InputGammaValueInput.swift",
        r"static let step\s*=\s*([0-9.]+)",
    ),
}

# macOS `CommitSlider.keyDown`: `step * (shift ? 10 : 1)`.
MAC_SHIFT_MULTIPLIER = 10.0


def mac_parity_problems():
    """맥 상수와 XAML 이 어긋나면 알립니다. 맥 트리가 없으면 조용히 넘어갑니다."""
    mac = ROOT.parent / "negaflow-mac"
    if not mac.is_dir():
        return []
    found = {}
    for path in sorted(VIEWS.rglob("*.xaml")):
        text = path.read_text(encoding="utf-8")
        for opening in SLIDER.findall(text):
            attributes = dict(ATTRIBUTE.findall(opening))
            name = attributes.get("x:Name")
            if name in MAC_BOUND_SLIDERS:
                found[name] = (path, attributes)

    problems = []
    for name, (range_file, range_pattern, step_file, step_pattern) in MAC_BOUND_SLIDERS.items():
        if name not in found:
            problems.append(f"{name}: XAML 에서 찾지 못했습니다 - 이름이 바뀌었으면 이 표도 고치십시오.")
            continue
        path, attributes = found[name]
        where = f"{path.relative_to(ROOT)} · {name}"

        range_source = mac / range_file
        step_source = mac / step_file
        if not range_source.is_file() or not step_source.is_file():
            problems.append(f"{where}: 맥 원본을 찾지 못했습니다 ({range_file} / {step_file}).")
            continue
        range_match = re.search(range_pattern, range_source.read_text(encoding="utf-8"))
        step_match = re.search(step_pattern, step_source.read_text(encoding="utf-8"))
        if not range_match or not step_match:
            problems.append(f"{where}: 맥 상수를 읽지 못했습니다 - 무늬가 낡았습니다.")
            continue

        expected = {
            "Minimum": float(range_match.group(1)),
            "Maximum": float(range_match.group(2)),
            "StepFrequency": float(step_match.group(1)),
            "SmallChange": float(step_match.group(1)),
            "LargeChange": float(step_match.group(1)) * MAC_SHIFT_MULTIPLIER,
        }
        for attribute, want in expected.items():
            got = number(attributes.get(attribute, ""))
            if got is None:
                problems.append(f"{where}: {attribute} 가 없습니다 (맥 값 {want:g}).")
            elif abs(got - want) > 1e-9:
                problems.append(
                    f"{where}: {attribute}={got:g} 인데 맥은 {want:g} 입니다."
                )
    return problems


def main():
    problems = mac_parity_problems()
    for path in sorted(VIEWS.rglob("*.xaml")):
        text = path.read_text(encoding="utf-8")
        for opening in SLIDER.findall(text):
            ordered = ATTRIBUTE.findall(opening)
            attributes = dict(ordered)
            where = f"{path.relative_to(ROOT)} · {describe(attributes)}"

            # XAML 은 속성을 **적힌 차례대로** 넣습니다. `Minimum` 이 `Maximum` 보다 먼저
            # 오면 그 순간 `Maximum` 은 아직 기본값 1 이라, `Minimum` 이 1 을 넘으면
            # `Failed to assign to property 'RangeBase.Minimum'` 으로 **창이 아예 뜨지
            # 않습니다.** 실측 2026-09-03: 복제 크기 슬라이더에 `Minimum="4"` 를
            # `Maximum="512"` 앞에 적었다가 앱이 부팅 중에 죽었습니다.
            names = [name for name, _ in ordered]
            if "Minimum" in names and "Maximum" in names:
                if names.index("Minimum") < names.index("Maximum"):
                    early = number(attributes["Minimum"])
                    if early is not None and early > DEFAULT_MAXIMUM:
                        problems.append(
                            f"{where}: Minimum(\"{attributes['Minimum']}\") 이 Maximum 보다 "
                            "먼저 적혔습니다 - 그 순간 Maximum 은 기본값 1 이라 파싱이 터지고 "
                            "창이 뜨지 않습니다. Maximum 을 먼저 적으세요."
                        )

            # 바인딩이나 스타일로 넘기는 값은 여기서 읽을 수 없습니다. 리터럴만 봅니다.
            step = attributes.get("StepFrequency")
            if step is not None:
                parsed = number(step)
                if parsed is None:
                    pass
                elif parsed <= 0.0:
                    problems.append(
                        f"{where}: StepFrequency=\"{step}\" - 0 이하면 손잡이를 잡는 순간 "
                        "NaN 으로 창이 내려앉습니다."
                    )

            low = number(attributes.get("Minimum", "")) if "Minimum" in attributes else None
            high = number(attributes.get("Maximum", "")) if "Maximum" in attributes else None
            if low is not None and high is not None:
                if low > high:
                    problems.append(f"{where}: Minimum({low}) > Maximum({high}).")
                elif step is not None:
                    parsed = number(step)
                    if parsed is not None and parsed > (high - low):
                        problems.append(
                            f"{where}: StepFrequency({parsed}) 가 범위({high - low}) 보다 큽니다 - "
                            "슬라이더가 움직이지 않습니다."
                        )

    if problems:
        print("슬라이더 범위 문제:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print("슬라이더 범위: 이상 없음")
    return 0


if __name__ == "__main__":
    sys.exit(main())
