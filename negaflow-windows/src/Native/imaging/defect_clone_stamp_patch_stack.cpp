#include "defect_clone_stamp_patch_stack.h"

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace negaflow::imaging::clone_stamp_detail {

[[nodiscard]] std::uint16_t encode_linear16(const float value) noexcept {
    const double scaled = static_cast<double>(std::clamp(value, 0.0F, 1.0F)) *
        65'535.0;
    return static_cast<std::uint16_t>(std::floor(scaled + 0.5));
}

[[nodiscard]] float decode_linear16(const std::uint16_t value) noexcept {
    return static_cast<float>(value) / 65'535.0F;
}

[[nodiscard]] bool contains(
    const StoredPatch& patch,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    return x >= patch.x && y >= patch.y &&
        x - patch.x < patch.width && y - patch.y < patch.height;
}

[[nodiscard]] negaflow::core::Rgba32F patch_pixel(
    const StoredPatch& patch,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    const std::size_t index =
        (static_cast<std::size_t>(y - patch.y) * patch.width + (x - patch.x)) *
        4U;
    return {
        decode_linear16(patch.rgba16[index]),
        decode_linear16(patch.rgba16[index + 1U]),
        decode_linear16(patch.rgba16[index + 2U]),
        1.0F,
    };
}

[[nodiscard]] negaflow::core::Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    for (auto patch = patches.rbegin(); patch != patches.rend(); ++patch) {
        if (contains(*patch, x, y)) {
            return patch_pixel(*patch, x, y);
        }
    }
    return base.pixels[static_cast<std::size_t>(y) * base.stride_pixels + x];
}

void composite_patch(
    WorkingImage& image,
    const StoredPatch& patch,
    const float strength) noexcept {
    const float inverse = 1.0F - strength;
    for (std::uint32_t y = 0U; y < patch.height; ++y) {
        for (std::uint32_t x = 0U; x < patch.width; ++x) {
            const std::size_t patch_index =
                (static_cast<std::size_t>(y) * patch.width + x) * 4U;
            auto& destination = image.pixels[
                static_cast<std::size_t>(patch.y + y) * image.stride_pixels +
                patch.x + x];
            destination.red =
                decode_linear16(patch.rgba16[patch_index]) * strength +
                destination.red * inverse;
            destination.green =
                decode_linear16(patch.rgba16[patch_index + 1U]) * strength +
                destination.green * inverse;
            destination.blue =
                decode_linear16(patch.rgba16[patch_index + 2U]) * strength +
                destination.blue * inverse;
            destination.alpha = strength + destination.alpha * inverse;
        }
    }
}

}  // namespace negaflow::imaging::clone_stamp_detail
