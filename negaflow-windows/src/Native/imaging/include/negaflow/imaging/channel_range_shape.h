#pragma once

#include <array>
#include <optional>

namespace negaflow::imaging {

// 자동 밸런스 OFF 의 고정 반전은 세 채널에 같은 밀도 범위를 쓴다. 장치 × 필름이 정하는 실제 채널
// 범위비만큼 회색이 기운다. 한 프레임의 장면 측정(최농부 p0.2, 1.8D 상한)에서 채널 범위의 "모양"
// (R·G·B 곱, 기하평균 1)을 뽑는 규칙이다. macOS `ChannelRangeCalibration` 과 같은 규칙이다.

// 프레임 측정에 쓰는 밀도 상한(D). 자동 밸런스가 쓰는 값과 같다.
inline constexpr float channel_range_density_limit = 1.8F;

// 한 채널이 상한에 닿으면 그 채널의 진짜 범위는 더 크므로 모양이 잘려 있다. 그런 측정은 쓰지 않는다.
[[nodiscard]] bool channel_range_measurement_clipped(const std::array<float, 3>& measured) noexcept;

// 유한하고 양수이며 허용 범위(0.5…2.0) 안일 때만 돌려주고 기하평균 1 로 맞춘다.
[[nodiscard]] std::optional<std::array<float, 3>> sanitize_channel_range(
    const std::array<float, 3>& value) noexcept;

// 측정(`SceneRangeMeasurement::dmax_normalized`)에서 프레임의 모양을 뽑는다. 잘렸거나 비정상이면 비어 있다.
[[nodiscard]] std::optional<std::array<float, 3>> channel_range_shape(
    const std::array<float, 3>& measured_dmax) noexcept;

}  // namespace negaflow::imaging
