#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging {

[[nodiscard]] bool resample_infrared_plane_to_extent(
    std::span<const float> source,
    std::uint32_t source_width,
    std::uint32_t source_height,
    std::uint32_t output_width,
    std::uint32_t output_height,
    std::vector<float>& output);

}  // namespace negaflow::imaging
