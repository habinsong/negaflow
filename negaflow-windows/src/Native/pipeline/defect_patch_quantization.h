#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace negaflow::pipeline::defect_patch_detail {

// Core Image materializes every GrainMend patch as linear RGBA16 before the
// layer strength is composited. Keep this boundary shared by Region and IR.
[[nodiscard]] inline std::uint16_t encode_linear16(const float value) noexcept {
    const double encoded = std::floor(
        static_cast<double>(std::clamp(value, 0.0F, 1.0F)) * 65'535.0 + 0.5);
    return static_cast<std::uint16_t>(encoded);
}

[[nodiscard]] inline float decode_linear16(const std::uint16_t value) noexcept {
    return static_cast<float>(value) / 65'535.0F;
}

[[nodiscard]] inline float quantize_linear16(const float value) noexcept {
    return decode_linear16(encode_linear16(value));
}

[[nodiscard]] inline float composited_patch_strength(const double value) noexcept {
    return value < 0.999 ? static_cast<float>(value) : 1.0F;
}

}  // namespace negaflow::pipeline::defect_patch_detail
