#include "defect_heal_brush_patch_stack.h"

#include "negaflow/imaging/coreimage_gaussian.h"
#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::heal_brush_detail {

bool contains(
    const StoredPatch& patch,
    const int x,
    const int y) noexcept {
    return x >= patch.left && y >= patch.top &&
        x - patch.left < patch.width && y - patch.top < patch.height;
}

Rgba32F full_strength_pixel(
    const WorkingImage& base,
    const std::vector<StoredPatch>& patches,
    const int x,
    const int y) noexcept {
    for (auto patch = patches.rbegin(); patch != patches.rend(); ++patch) {
        if (contains(*patch, x, y)) {
            return patch->pixels[
                static_cast<std::size_t>(y - patch->top) * patch->width +
                static_cast<std::size_t>(x - patch->left)];
        }
    }
    return base.pixels[
        static_cast<std::size_t>(y) * base.stride_pixels +
        static_cast<std::size_t>(x)];
}

std::vector<float> gaussian_radius_one(
    const std::vector<float>& source,
    const int width,
    const int height) {
    constexpr float radius = 1.0F;
    const float sigma = coreimage_gaussian_effective_sigma(radius);
    const int support_radius = coreimage_gaussian_support_radius(radius);
    std::vector<float> weights(
        static_cast<std::size_t>(support_radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -support_radius; offset <= support_radius; ++offset) {
        const float value = std::exp(
            -static_cast<float>(offset * offset) / (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + support_radius)] = value;
        total += value;
    }
    for (float& weight : weights) {
        weight /= total;
    }
    std::vector<float> horizontal(source.size(), 0.0F);
    std::vector<float> output(source.size(), 0.0F);
    const std::uint64_t work_units = static_cast<std::uint64_t>(source.size()) *
        static_cast<std::uint64_t>(support_radius * 2 + 1);
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(height),
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (int x = 0; x < width; ++x) {
                    float value = 0.0F;
                    for (int offset = -support_radius;
                         offset <= support_radius;
                         ++offset) {
                        const int sample_x = x + offset;
                        if (sample_x >= 0 && sample_x < width) {
                            value += source[
                                static_cast<std::size_t>(y) * width + sample_x] *
                                weights[static_cast<std::size_t>(offset + support_radius)];
                        }
                    }
                    horizontal[static_cast<std::size_t>(y) * width + x] = value;
                }
            }
        });
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(width),
        work_units,
        [&](const std::uint32_t first_column, const std::uint32_t column_count) noexcept {
            for (std::uint32_t x = first_column; x < first_column + column_count; ++x) {
                for (int y = 0; y < height; ++y) {
                    float value = 0.0F;
                    for (int offset = -support_radius;
                         offset <= support_radius;
                         ++offset) {
                        const int sample_y = y + offset;
                        if (sample_y >= 0 && sample_y < height) {
                            value += horizontal[
                                static_cast<std::size_t>(sample_y) * width + x] *
                                weights[static_cast<std::size_t>(offset + support_radius)];
                        }
                    }
                    output[static_cast<std::size_t>(y) * width + x] = value;
                }
            }
        });
    return output;
}

float quantize_linear16(const float value) noexcept {
    const double encoded = std::floor(
        static_cast<double>(std::clamp(value, 0.0F, 1.0F)) * 65'535.0 + 0.5);
    return static_cast<float>(encoded / 65'535.0);
}

std::size_t composite_patches(
    WorkingImage& image,
    const std::vector<StoredPatch>& patches,
    const float strength) {
    if (patches.empty()) {
        return 0U;
    }
    int covered_left = static_cast<int>(image.width);
    int covered_top = static_cast<int>(image.height);
    int covered_right = 0;
    int covered_bottom = 0;
    for (const StoredPatch& patch : patches) {
        covered_left = std::min(covered_left, patch.left);
        covered_top = std::min(covered_top, patch.top);
        covered_right = std::max(covered_right, patch.left + patch.width);
        covered_bottom = std::max(covered_bottom, patch.top + patch.height);
    }
    const int covered_width = covered_right - covered_left;
    const int covered_height = covered_bottom - covered_top;
    std::vector<std::uint8_t> covered(
        static_cast<std::size_t>(covered_width) * covered_height,
        0U);
    for (auto current = patches.rbegin(); current != patches.rend(); ++current) {
        const StoredPatch& patch = *current;
        for (int y = 0; y < patch.height; ++y) {
            for (int x = 0; x < patch.width; ++x) {
                const std::size_t patch_pixel =
                    static_cast<std::size_t>(y) * patch.width + x;
                const std::size_t image_pixel =
                    static_cast<std::size_t>(patch.top + y) *
                        image.stride_pixels +
                    static_cast<std::size_t>(patch.left + x);
                const std::size_t packed_pixel =
                    static_cast<std::size_t>(patch.top + y - covered_top) * covered_width +
                    static_cast<std::size_t>(patch.left + x - covered_left);
                if (covered[packed_pixel] != 0U) {
                    continue;
                }
                covered[packed_pixel] = 1U;
                Rgba32F& destination = image.pixels[image_pixel];
                const Rgba32F full = patch.pixels[patch_pixel];
                const float keep = 1.0F - strength;
                destination.red = destination.red * keep +
                    quantize_linear16(full.red) * strength;
                destination.green = destination.green * keep +
                    quantize_linear16(full.green) * strength;
                destination.blue = destination.blue * keep +
                    quantize_linear16(full.blue) * strength;
            }
        }
    }
    return covered.size();
}

}  // namespace negaflow::imaging::heal_brush_detail
