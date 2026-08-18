#include "local_dodge_burn_blur.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <new>

namespace negaflow::imaging::local_dodge_burn_detail {

[[nodiscard]] std::vector<float> box_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const int radius) {
    if (radius <= 0) {
        return source;
    }
    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    const float inverse = 1.0F / static_cast<float>(radius * 2 + 1);
    // Each sweep carries a running sum along its own line and touches no other, so the
    // horizontal pass splits by row and the vertical one by column. Same arithmetic in
    // the same order within a line, so the totals are identical.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
    negaflow::core::for_each_row_block(
        height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_x = static_cast<std::uint32_t>(std::clamp(
                offset,
                0,
                static_cast<int>(width) - 1));
            sum += source[index_of(sample_x, y, width)];
        }
        for (std::uint32_t x = 0U; x < width; ++x) {
            horizontal[index_of(x, y, width)] = sum * inverse;
            const auto remove_x = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(x) - radius,
                0,
                static_cast<int>(width) - 1));
            const auto add_x = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(x) + radius + 1,
                0,
                static_cast<int>(width) - 1));
            sum += source[index_of(add_x, y, width)] -
                   source[index_of(remove_x, y, width)];
        }
      }
        });
    negaflow::core::for_each_row_block(
        width,
        work_units,
        [&](const std::uint32_t first_column, const std::uint32_t column_count) noexcept {
      for (std::uint32_t x = first_column; x < first_column + column_count; ++x) {
        float sum = 0.0F;
        for (int offset = -radius; offset <= radius; ++offset) {
            const auto sample_y = static_cast<std::uint32_t>(std::clamp(
                offset,
                0,
                static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, sample_y, width)];
        }
        for (std::uint32_t y = 0U; y < height; ++y) {
            result[index_of(x, y, width)] = sum * inverse;
            const auto remove_y = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(y) - radius,
                0,
                static_cast<int>(height) - 1));
            const auto add_y = static_cast<std::uint32_t>(std::clamp(
                static_cast<int>(y) + radius + 1,
                0,
                static_cast<int>(height) - 1));
            sum += horizontal[index_of(x, add_y, width)] -
                   horizontal[index_of(x, remove_y, width)];
        }
      }
        });
    return result;
}

[[nodiscard]] std::vector<float> direct_gaussian_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const float sigma) {
    const int radius = std::max(1, static_cast<int>(std::ceil(3.0F * sigma)));
    std::vector<float> weights(static_cast<std::size_t>(radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -radius; offset <= radius; ++offset) {
        const float weight = std::exp(
            -static_cast<float>(offset * offset) / (2.0F * sigma * sigma));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight /= total;
    }

    std::vector<float> horizontal(source.size());
    std::vector<float> result(source.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const auto sample_x = static_cast<std::uint32_t>(std::clamp(
                    static_cast<int>(x) + offset,
                    0,
                    static_cast<int>(width) - 1));
                value += source[index_of(sample_x, y, width)] *
                         weights[static_cast<std::size_t>(offset + radius)];
            }
            horizontal[index_of(x, y, width)] = value;
        }
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float value = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const auto sample_y = static_cast<std::uint32_t>(std::clamp(
                    static_cast<int>(y) + offset,
                    0,
                    static_cast<int>(height) - 1));
                value += horizontal[index_of(x, sample_y, width)] *
                         weights[static_cast<std::size_t>(offset + radius)];
            }
            result[index_of(x, y, width)] = value;
        }
    }
    return result;
}

[[nodiscard]] std::vector<float> scalable_gaussian_blur(
    const std::vector<float>& source,
    const std::uint32_t width,
    const std::uint32_t height,
    const float sigma) {
    constexpr int passes = 3;
    const float ideal_width = std::sqrt(
        12.0F * sigma * sigma / static_cast<float>(passes) + 1.0F);
    int lower_width = static_cast<int>(std::floor(ideal_width));
    if ((lower_width & 1) == 0) {
        --lower_width;
    }
    lower_width = std::max(1, lower_width);
    const int upper_width = lower_width + 2;
    const float numerator =
        12.0F * sigma * sigma -
        static_cast<float>(passes * lower_width * lower_width +
                           4 * passes * lower_width + 3 * passes);
    const int lower_passes = std::clamp(
        static_cast<int>(std::lround(
            numerator / static_cast<float>(-4 * lower_width - 4))),
        0,
        passes);

    std::vector<float> result = source;
    for (int pass = 0; pass < passes; ++pass) {
        const int width_for_pass =
            pass < lower_passes ? lower_width : upper_width;
        result = box_blur(
            result,
            width,
            height,
            (width_for_pass - 1) / 2);
    }
    return result;
}

void soften_mask(
    MaskResult& mask,
    const WorkingImage& image,
    const float sigma) {
    if (sigma <= mask_blur_identity_threshold) {
        return;
    }
    const std::size_t bytes = mask.weights.size() * sizeof(float);
    mask.scratch_peak_bytes = std::max(mask.scratch_peak_bytes, bytes * 3U);
    mask.weights = sigma <= direct_gaussian_maximum_sigma
        ? direct_gaussian_blur(mask.weights, image.width, image.height, sigma)
        : scalable_gaussian_blur(mask.weights, image.width, image.height, sigma);
    for (float& weight : mask.weights) {
        weight = clamp_unit(weight);
    }
}

}  // namespace negaflow::imaging::local_dodge_burn_detail
