#pragma once

#include "infrared_detection_types.h"

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 성분 화소를 (dx, dy) 만큼 옮겨 가시 밀도와 곱한 가중 점수입니다.
[[nodiscard]] double weighted_score(
    const RawComponent& component,
    std::span<const float> weights,
    std::span<const float> visible,
    std::uint32_t width,
    std::uint32_t height,
    std::int32_t dx,
    std::int32_t dy);

// 최고점만 골라 쓰기 때문에 생기는 선택 편향입니다. 확정 세기에서 이만큼 빼지 않으면
// 잡음의 최고점을 결함 세기로 착각합니다.
[[nodiscard]] float selection_bias(float significance) noexcept;

// IR 성분 하나가 가시 채널의 어느 자리에 대응하는지 찾고, 그 대응이 잡음보다 유의한지
// 판정합니다. 유의도가 기준 미만이거나 세기가 양수가 아니면 채택하지 않습니다.
[[nodiscard]] bool confirm_component(
    const RawComponent& component,
    std::span<const float> density,
    std::span<const float> visible,
    std::uint32_t width,
    std::uint32_t height,
    float magnitude_floor,
    std::int32_t search,
    std::int32_t origin_x,
    std::int32_t origin_y,
    ConfirmedDefect& confirmed);

struct ConsensusOffset final {
    std::int32_t x{0};
    std::int32_t y{0};
};

[[nodiscard]] ConsensusOffset coarse_consensus_offset(
    const std::vector<RawComponent>& candidates,
    std::span<const float> density,
    std::span<const float> visible,
    std::uint32_t width,
    std::uint32_t height,
    float magnitude_floor,
    std::int32_t search);

}  // namespace negaflow::imaging::infrared_detail
