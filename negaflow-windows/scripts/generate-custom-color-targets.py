#!/usr/bin/env python3
"""custom-3 계수 표와 macOS 기준값을 네이티브 소스에 연결합니다."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def array(values):
    return "{" + ", ".join(format(float(v), ".17g") for v in values) + "}"


def profiles(spec):
    source = '''// generate-custom-color-targets.py로 생성합니다. 계수 원본: assets/custom-targets/custom-3.json
#include "negaflow/imaging/custom_color_target.h"
#include <cmath>

namespace negaflow::imaging {
namespace {
CustomColorTargetProfile prepare(CustomColorTargetProfile p) noexcept {
    constexpr std::array<double, 10> x{0, 5, 10, 20, 35, 50, 65, 80, 90, 100};
    std::array<double, 9> h{}, d{};
    for (std::size_t i = 0; i < 9; ++i) {
        h[i] = x[i + 1] - x[i];
        d[i] = (p.tone[i + 1] - p.tone[i]) / h[i];
    }
    for (std::size_t i = 1; i < 9; ++i) {
        if (d[i - 1] * d[i] > 0) {
            const double w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1];
            p.slopes[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
        }
    }
    const auto endpoint = [](double h0, double h1, double d0, double d1) noexcept {
        const double value = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
        if (value * d0 <= 0) { return 0.0; }
        if (d0 * d1 < 0 && std::abs(value) > 3 * std::abs(d0)) { return 3 * d0; }
        return value;
    };
    p.slopes[0] = endpoint(h[0], h[1], d[0], d[1]);
    p.slopes[9] = endpoint(h[8], h[7], d[8], d[7]);
    return p;
}
const std::array<CustomColorTargetProfile, 18> profiles{{
'''
    fields = {"tone": "tone_l", "gain": "chroma_gain", "density": "density_k",
              "hue_shadow": "hue_shadow", "hue_mid": "hue_mid", "hue_high": "hue_high",
              "highlight_hue": "highlight_hue_bias"}
    for target in spec["targets"]:
        source += f'    // {target["id"]} ({target["native_id"]})\n    prepare({{\n'
        for field, key in fields.items():
            source += f'        .{field} = {array(target[key])},\n'
        source += "        .controls = " + array([target[k] for k in ["shadow_chroma", "highlight_start", "highlight_softness", "highlight_tone_mix"]]) + ",\n"
        for key in ["tint_shadow", "tint_mid", "tint_high"]:
            source += f'        .{key} = {array(target[key])},\n'
        source += "    }),\n"
    return source + '''}};
} // namespace
const CustomColorTargetProfile* custom_color_target_profile(std::uint32_t target) noexcept {
    if (target < first_custom_color_target || target > last_custom_color_target) { return nullptr; }
    return &profiles[target - first_custom_color_target];
}
} // namespace negaflow::imaging
'''


def fixtures(spec):
    fixture = json.loads((ROOT.parent / "negaflow-mac/Tests/ChromabaseTests/Fixtures/CustomColorTargets.json").read_text())
    assert [t["id"] for t in fixture["targets"]] == [t["id"] for t in spec["targets"]]
    source = '''// macOS의 독립 기준값을 그대로 옮깁니다. generate-custom-color-targets.py로 생성합니다.
#pragma once
#include <cstdint>
struct CustomTargetSample { std::uint32_t target; double lch[3]; double expected[3]; };
inline constexpr CustomTargetSample custom_target_samples[] = {
'''
    for index, target in enumerate(fixture["targets"], 7):
        for sample in target["samples"]:
            source += f'    {{{index}U, {array(sample["input"])}, {array(sample["expected"])}}},\n'
    return source + "};\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    spec = json.loads((ROOT / "assets/custom-targets/custom-3.json").read_text())
    assert spec["revision"] == "custom-3"
    assert spec["tone_input_l"] == [0, 5, 10, 20, 35, 50, 65, 80, 90, 100]
    assert spec["chroma_rolloff_start"] == spec["chroma_rolloff_range"] == 48
    assert [t["native_id"] for t in spec["targets"]] == list(range(7, 25))
    outputs = {"src/Native/imaging/custom_color_target_profiles.cpp": profiles(spec),
               "tests/Native.UnitTests/Fixtures/custom_color_target_samples.h": fixtures(spec)}
    for name, text in outputs.items():
        path = ROOT / name
        if args.check:
            assert path.read_text() == text, f"계수 또는 기준값 불일치: {name}"
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    print("Custom 18개 계수와 macOS 기준값 일치")


if __name__ == "__main__":
    main()
