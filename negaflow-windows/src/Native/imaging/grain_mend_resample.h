#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include <array>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// Mirrors the whole-frame macOS order: resize in the linear working domain,
// then render the three analysis channels in sRGB encoding.
void render_detection_rgb(
    const WorkingImage& image,
    std::uint32_t output_width,
    std::uint32_t output_height,
    std::array<std::vector<float>, 3U>& channels);

// Samples the transformed one-channel defect mask at a full-resolution pixel.
// Core Image evaluates transformed masks continuously, so the returned value is
// a blend weight rather than a binary inclusion flag.
[[nodiscard]] float sample_transformed_mask(
    const std::vector<std::uint8_t>& mask,
    std::uint32_t mask_width,
    std::uint32_t mask_height,
    std::uint32_t output_width,
    std::uint32_t output_height,
    std::uint32_t output_x,
    std::uint32_t output_y) noexcept;

}  // namespace negaflow::imaging::grain_mend_detail
