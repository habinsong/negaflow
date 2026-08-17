#include "grain_mend_scratch_response_map.h"

#include <algorithm>

namespace negaflow::imaging::grain_mend_detail {

ScratchResponseMap::ScratchResponseMap(
    const std::uint32_t source_width,
    const std::uint32_t source_height) {
    width_ = std::max(1U, (source_width + downsample - 1U) / downsample);
    height_ = std::max(1U, (source_height + downsample - 1U) / downsample);
    values_.assign(
        static_cast<std::size_t>(width_) * static_cast<std::size_t>(height_),
        0.0F);
}

void ScratchResponseMap::merge(
    const std::vector<float>& tile,
    const std::uint32_t tile_width,
    const std::uint32_t tile_height,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y) {
    if (tile.size() !=
        static_cast<std::size_t>(tile_width) *
            static_cast<std::size_t>(tile_height)) {
        return;
    }
    for (std::uint32_t y = 0U; y < tile_height; ++y) {
        const std::uint32_t global_y = (origin_y + y) / downsample;
        if (global_y >= height_) {
            continue;
        }
        const std::size_t row_base =
            static_cast<std::size_t>(global_y) * width_;
        const std::size_t tile_row =
            static_cast<std::size_t>(y) * tile_width;
        for (std::uint32_t x = 0U; x < tile_width; ++x) {
            const std::uint32_t global_x = (origin_x + x) / downsample;
            if (global_x >= width_) {
                continue;
            }
            const float value = tile[tile_row + x];
            const std::size_t index = row_base + global_x;
            if (value > values_[index]) {
                values_[index] = value;
            }
        }
    }
}

bool ScratchResponseMap::value(
    const std::uint32_t x,
    const std::uint32_t y,
    float& result) const noexcept {
    const std::uint32_t map_x = x / downsample;
    const std::uint32_t map_y = y / downsample;
    if (map_x >= width_ || map_y >= height_) {
        return false;
    }
    result = values_[static_cast<std::size_t>(map_y) * width_ + map_x];
    return true;
}

}  // namespace negaflow::imaging::grain_mend_detail
