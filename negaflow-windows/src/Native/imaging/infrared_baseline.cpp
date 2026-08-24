#include "infrared_baseline.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::imaging::infrared_detail {

std::vector<float> optical_density(
    const std::span<const float> plane,
    const std::span<const float> baseline) {
    std::vector<float> density(plane.size(), 0.0F);
    const auto fill = [&](const std::size_t first, const std::size_t count) noexcept {
        const std::size_t end = first + count;
        for (std::size_t index = first; index < end; ++index) {
            const float value = std::max(plane[index], tuning::kPlaneFloor);
            const float base = std::max(baseline[index], tuning::kPlaneFloor);
            if (base > value) {
                density[index] = std::log(base / value);
            }
        }
    };
    if (density.size() > std::numeric_limits<std::uint32_t>::max()) {
        fill(0U, density.size());
        return density;
    }
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(density.size()),
        density.size(),
        [&](const std::uint32_t first, const std::uint32_t count) noexcept {
            fill(first, count);
        });
    return density;
}

SignalStatistics signal_statistics(
    const std::span<const float> density,
    const std::vector<std::uint8_t>& excluded,
    const double sensitivity) {
    std::vector<float> samples{};
    const std::size_t step = std::max<std::size_t>(1U, density.size() / 200000U);
    samples.reserve(density.size() / step + 1U);
    for (std::size_t index = 0U; index < density.size(); index += step) {
        if (excluded[index] == 0U) {
            samples.push_back(density[index]);
        }
    }
    if (samples.size() <= 256U) {
        return {};
    }
    std::sort(samples.begin(), samples.end());
    const auto at = [&](const double q) {
        return samples[static_cast<std::size_t>(
            q * static_cast<double>(samples.size() - 1U))];
    };
    const float floor = at(0.5);
    const float sigma = std::max((at(0.75) - floor) / 0.6745F, 0.0F);
    const float multiplier = static_cast<float>(19.0 - 11.0 * sensitivity);
    return SignalStatistics{
        floor,
        sigma,
        std::max(floor + multiplier * sigma, floor + 1.0e-3F)};
}

}  // namespace negaflow::imaging::infrared_detail
