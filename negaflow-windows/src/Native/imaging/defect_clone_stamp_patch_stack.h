#pragma once

#include "defect_clone_stamp_types.h"

#include "negaflow/core/pixel.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::clone_stamp_detail {

[[nodiscard]] std::uint16_t encode_linear16(float value) noexcept;

[[nodiscard]] float decode_linear16(std::uint16_t value) noexcept;

// 이 패치가 그 화소를 덮는가.
[[nodiscard]] bool contains(
    const StoredPatch& patch,
    std::uint32_t x,
    std::uint32_t y) noexcept;

[[nodiscard]] negaflow::core::Rgba32F patch_pixel(
    const StoredPatch& patch,
    std::uint32_t x,
    std::uint32_t y) noexcept;

// 이미 만든 패치를 나중 것부터 훑어 그 화소의 100% 강도 값을 냅니다. 없으면 원본을
// 읽습니다 - 겹친 획이 앞 획의 결과를 원본으로 삼게 하려는 것입니다.
[[nodiscard]] negaflow::core::Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    std::uint32_t x,
    std::uint32_t y) noexcept;

// 패치 하나를 강도만큼 이미지에 앉힙니다.
void composite_patch(
    WorkingImage& image,
    const StoredPatch& patch,
    float strength) noexcept;

}  // namespace negaflow::imaging::clone_stamp_detail
