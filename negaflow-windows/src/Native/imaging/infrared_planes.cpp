#include "infrared_planes.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cstddef>
#include <queue>
#include <utility>

namespace negaflow::imaging::infrared_detail {

float quantile(std::vector<float>& values, const double q) {
    std::sort(values.begin(), values.end());
    const auto index = static_cast<std::size_t>(
        std::clamp(q, 0.0, 1.0) * static_cast<double>(values.size() - 1U));
    return values[index];
}

float percentile(
    const std::span<const float> values,
    const std::vector<std::uint8_t>& excluded,
    const double q) {
    std::vector<float> samples{};
    const std::size_t step = std::max<std::size_t>(1U, values.size() / 100000U);
    samples.reserve(values.size() / step + 1U);
    for (std::size_t index = 0U; index < values.size(); index += step) {
        if (excluded.empty() || excluded[index] == 0U) {
            samples.push_back(values[index]);
        }
    }
    return samples.empty() ? 0.0F : quantile(samples, q);
}

std::vector<float> shift_plane(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy,
    std::vector<std::uint8_t>& excluded) {
    if (dx == 0 && dy == 0) return std::vector<float>(source.begin(), source.end());
    std::vector<float> output(source.size(), 0.0F);
    negaflow::core::for_each_row_block(
        height,
        source.size() * 3U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < width; ++x) {
                    const std::int32_t source_x = static_cast<std::int32_t>(x) + dx;
                    const std::int32_t source_y = static_cast<std::int32_t>(y) + dy;
                    const std::size_t target = static_cast<std::size_t>(y) * width + x;
                    if (source_x >= 0 && source_y >= 0 &&
                        source_x < static_cast<std::int32_t>(width) &&
                        source_y < static_cast<std::int32_t>(height)) {
                        output[target] = source[static_cast<std::size_t>(source_y) * width +
                            static_cast<std::uint32_t>(source_x)];
                    } else {
                        excluded[target] = 1U;
                    }
                }
            }
        });
    return output;
}

void exclude_border_dark(
    const std::span<const float> plane,
    const std::uint32_t width,
    const std::uint32_t height,
    const float threshold,
    const std::uint32_t rim,
    std::vector<std::uint8_t>& excluded) {
    const auto dark = [&](const std::uint32_t x, const std::uint32_t y) {
        return plane[static_cast<std::size_t>(y) * width + x] < threshold;
    };
    std::vector<std::uint8_t> margin(excluded.size(), 0U);
    std::queue<std::pair<std::uint32_t, std::uint32_t>> pending{};
    const auto seed = [&](const std::uint32_t x, const std::uint32_t y) {
        const std::size_t index = static_cast<std::size_t>(y) * width + x;
        if (margin[index] == 0U && dark(x, y)) {
            margin[index] = 1U;
            pending.emplace(x, y);
        }
    };
    for (std::uint32_t x = 0U; x < width; ++x) {
        seed(x, 0U);
        seed(x, height - 1U);
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        seed(0U, y);
        seed(width - 1U, y);
    }
    while (!pending.empty()) {
        const auto [x, y] = pending.front();
        pending.pop();
        if (x > 0U) seed(x - 1U, y);
        if (x + 1U < width) seed(x + 1U, y);
        if (y > 0U) seed(x, y - 1U);
        if (y + 1U < height) seed(x, y + 1U);
    }
    if (rim == 0U) {
        negaflow::core::for_each_row_block(
            height,
            excluded.size() * 2U,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                const std::size_t first = static_cast<std::size_t>(first_row) * width;
                const std::size_t end = static_cast<std::size_t>(first_row + row_count) * width;
                for (std::size_t index = first; index < end; ++index) {
                    excluded[index] = excluded[index] != 0U || margin[index] != 0U ? 1U : 0U;
                }
            });
        return;
    }
    std::vector<std::uint8_t> horizontal(margin.size(), 0U);
    negaflow::core::for_each_row_block(
        height,
        margin.size() * 2U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                std::uint32_t active = 0U;
                for (std::uint32_t x = 0U; x <= std::min(rim, width - 1U); ++x) {
                    active += margin[static_cast<std::size_t>(y) * width + x];
                }
                for (std::uint32_t x = 0U; x < width; ++x) {
                    horizontal[static_cast<std::size_t>(y) * width + x] =
                        active != 0U ? 1U : 0U;
                    if (x + rim + 1U < width) {
                        active += margin[static_cast<std::size_t>(y) * width + x + rim + 1U];
                    }
                    if (x >= rim) {
                        active -= margin[static_cast<std::size_t>(y) * width + x - rim];
                    }
                }
            }
        });
    negaflow::core::for_each_row_block(
        width,
        horizontal.size() * 2U,
        [&](const std::uint32_t first_column, const std::uint32_t column_count) noexcept {
            for (std::uint32_t x = first_column; x < first_column + column_count; ++x) {
                std::uint32_t active = 0U;
                for (std::uint32_t y = 0U; y <= std::min(rim, height - 1U); ++y) {
                    active += horizontal[static_cast<std::size_t>(y) * width + x];
                }
                for (std::uint32_t y = 0U; y < height; ++y) {
                    const std::size_t index = static_cast<std::size_t>(y) * width + x;
                    if (active != 0U) excluded[index] = 1U;
                    if (y + rim + 1U < height) {
                        active += horizontal[static_cast<std::size_t>(y + rim + 1U) * width + x];
                    }
                    if (y >= rim) {
                        active -= horizontal[static_cast<std::size_t>(y - rim) * width + x];
                    }
                }
            }
        });
}

}  // namespace negaflow::imaging::infrared_detail
