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

// 회색 <c>{v, v, v}</c> 의 Lab 밝기만입니다.
//
// 등급 커널은 화소마다 이것을 세 번 구합니다(중성 기준 한 번, 방향별 한 번씩). 회색은
// 세 채널이 같아서 <c>srgb_decode</c> 와 <c>lab_f</c> 를 한 번씩만 하면 되고, a·b 를
// 쓰지 않으므로 x·z 는 아예 구할 필요가 없습니다. <c>srgb_to_lab({v,v,v}).lightness</c>
// 와 **같은 식·같은 차례**라 결과는 비트 단위로 같습니다.
[[nodiscard]] double neutral_lab_lightness(double value) noexcept;

// Lab 을 sRGB 로 되돌립니다. 0…1 로 자르지 않습니다 - 자르면 색역 밖 화소가 어느 쪽으로
// 얼마나 나갔는지 알 수 없어져 gamut_scale 이 판단할 수 없습니다.
[[nodiscard]] Rgb lab_to_extended_srgb(Lab value) noexcept;

[[nodiscard]] double luma(Rgb value) noexcept;

// 정렬한 표본의 분위값입니다. 입력 벡터는 제자리에서 정렬됩니다.
[[nodiscard]] double percentile(std::vector<double>& values, double fraction);

}  // namespace negaflow::imaging::scanner_target_detail
