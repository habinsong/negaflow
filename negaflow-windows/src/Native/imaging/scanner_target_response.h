#pragma once

#include "scanner_target_profile.h"

#include <array>

namespace negaflow::imaging::scanner_target_detail {

// 톤 표를 이 밝기에서 읽습니다. 표 밖은 양 끝값으로 이어 붙입니다.
[[nodiscard]] double relative_tone(
    double value,
    const std::array<double, 9U>& xs,
    const std::array<double, 9U>& ys) noexcept;

// 이 밝기에서 채도를 얼마나 실을지입니다. `keep` 은 원본 채도를 지키는 비율입니다.
[[nodiscard]] double chroma_band_gain(
    double value,
    const TargetProfile& profile,
    double keep) noexcept;

// 이 밝기에서 중성축이 흐르는 (a, b) 만큼입니다.
[[nodiscard]] std::array<double, 2U> neutral_drift(
    double value,
    const TargetProfile& profile,
    double scale) noexcept;

// 이 색상각에서 채도 배율과 회전각입니다.
[[nodiscard]] std::array<double, 2U> hue_response(
    double hue,
    const TargetProfile& profile,
    double scale,
    double keep) noexcept;

// 화소 하나에 룩 전부를 실은 결과입니다. `reciprocal` 은 상대 프로파일을 되돌리는
// 방향으로 쓸 때 세웁니다.
[[nodiscard]] Rgb transformed_srgb(
    Rgb input,
    const TargetProfile& profile,
    const std::array<double, 9U>& tone,
    double scale,
    double chroma_keep,
    bool monochrome,
    bool reciprocal) noexcept;

// 같은 화소의 정방향과 역방향을 **한 번에** 냅니다.
//
// 등급 커널은 화소마다 `transformed_srgb` 를 두 번 부릅니다 — `reciprocal` 만 다르고
// 입력은 완전히 같습니다. 그래서 두 호출이 하는 일의 대부분이 **똑같은 값을 두 번**
// 구하는 것이었습니다: `srgb_to_lab(input)`, 중성 밝기, 톤 표 조회, 색상각, 색상 응답,
// 채도 밴드, 중성 흐름. `atan2` 는 한 호출 안에서도 두 번 불려 화소당 **네 번**이었습니다.
//
// 여기서는 그 공통 부분을 한 번만 구하고 방향에 따라 달라지는 것만 두 번 합니다.
// 각 값은 예전과 **같은 식·같은 차례**로 구하므로 결과는 비트 단위로 같습니다 —
// 근사가 아니라 중복 제거입니다.
struct TransformedPair final {
    Rgb candidate{};
    Rgb reciprocal{};
};

[[nodiscard]] TransformedPair transformed_srgb_pair(
    Rgb input,
    const TargetProfile& profile,
    const std::array<double, 9U>& tone,
    double scale,
    double chroma_keep,
    bool monochrome) noexcept;

// 결과가 색역 밖으로 나갔을 때, 원본 쪽으로 얼마나 되돌려야 안으로 들어오는지입니다.
// 그냥 자르면 색상이 돌아가므로 방향을 지키며 줄입니다.
[[nodiscard]] double gamut_scale(
    Rgb input,
    Rgb candidate,
    Rgb reciprocal) noexcept;

}  // namespace negaflow::imaging::scanner_target_detail
