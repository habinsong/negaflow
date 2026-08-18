#pragma once

#include "scanner_target_profile.h"

#include <vector>

namespace negaflow::imaging::scanner_target_detail {

[[nodiscard]] double clamp(double value, double low, double high) noexcept;

[[nodiscard]] double smoothstep(double low, double high, double value) noexcept;

[[nodiscard]] double srgb_encode(double value) noexcept;

[[nodiscard]] double srgb_decode(double value) noexcept;

[[nodiscard]] double lab_f(double value) noexcept;

[[nodiscard]] double lab_f_inverse(double value) noexcept;

[[nodiscard]] Lab srgb_to_lab(Rgb value) noexcept;

// Lab 을 sRGB 로 되돌립니다. 0…1 로 자르지 않습니다 - 자르면 색역 밖 화소가 어느 쪽으로
// 얼마나 나갔는지 알 수 없어져 gamut_scale 이 판단할 수 없습니다.
[[nodiscard]] Rgb lab_to_extended_srgb(Lab value) noexcept;

[[nodiscard]] double luma(Rgb value) noexcept;

// 정렬한 표본의 분위값입니다. 입력 벡터는 제자리에서 정렬됩니다.
[[nodiscard]] double percentile(std::vector<double>& values, double fraction);

}  // namespace negaflow::imaging::scanner_target_detail
