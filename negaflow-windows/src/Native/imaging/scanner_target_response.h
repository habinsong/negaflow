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

// 결과가 색역 밖으로 나갔을 때, 원본 쪽으로 얼마나 되돌려야 안으로 들어오는지입니다.
// 그냥 자르면 색상이 돌아가므로 방향을 지키며 줄입니다.
[[nodiscard]] double gamut_scale(
    Rgb input,
    Rgb candidate,
    Rgb reciprocal) noexcept;

}  // namespace negaflow::imaging::scanner_target_detail
