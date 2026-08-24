#include "infrared_confirmation.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <numeric>
#include <vector>

namespace negaflow::imaging::infrared_detail {

double weighted_score(
    const RawComponent& component,
    const std::span<const float> weights,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t dx,
    const std::int32_t dy) {
    double score = 0.0;
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const std::size_t pixel = component.pixels[ordinal];
        const auto x = static_cast<std::int32_t>(pixel % width) + dx;
        const auto y = static_cast<std::int32_t>(pixel / width) + dy;
        if (x >= 0 && y >= 0 && x < static_cast<std::int32_t>(width) &&
            y < static_cast<std::int32_t>(height)) {
            score += static_cast<double>(weights[ordinal]) *
                visible[static_cast<std::size_t>(y) * width +
                    static_cast<std::uint32_t>(x)];
        }
    }
    return score;
}

float selection_bias(const float significance) noexcept {
    const double x = static_cast<double>(tuning::kMinimumSignificance - significance);
    const double density = std::exp(-0.5 * x * x) /
        std::sqrt(2.0 * tuning::kPi);
    const double tail = 0.5 * std::erfc(x / std::sqrt(2.0));
    return tail > 1.0e-12 ? static_cast<float>(density / tail) : 0.0F;
}

bool confirm_component(
    const RawComponent& component,
    const std::span<const float> density,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const float magnitude_floor,
    const std::int32_t search,
    const std::int32_t origin_x,
    const std::int32_t origin_y,
    ConfirmedDefect& confirmed) {
    std::vector<float> weights(component.pixels.size(), 0.0F);
    double square_sum = 0.0;
    for (std::size_t ordinal = 0U; ordinal < component.pixels.size(); ++ordinal) {
        const float weight = std::max(0.0F, density[component.pixels[ordinal]] - magnitude_floor);
        weights[ordinal] = weight;
        square_sum += static_cast<double>(weight) * weight;
    }
    if (!(square_sum > 0.0)) return false;

    double best = -std::numeric_limits<double>::infinity();
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            const double score = weighted_score(
                component, weights, visible, width, height,
                dx + origin_x, dy + origin_y);
            if (score > best) {
                best = score;
                best_x = dx;
                best_y = dy;
            }
        }
    }
    if (!(best > 0.0)) return false;

    const auto extent = static_cast<std::int32_t>(
        std::min(component.max_x - component.min_x,
                 component.max_y - component.min_y) / 2U + 1U);
    const std::int32_t null_inner = 2 * extent + 2;
    std::vector<double> null_samples{};
    null_samples.reserve(static_cast<std::size_t>(2 * search + 1) *
                         static_cast<std::size_t>(2 * search + 1));
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            if (std::max(std::abs(dx), std::abs(dy)) >= null_inner) {
                null_samples.push_back(weighted_score(
                    component, weights, visible, width, height,
                    dx + origin_x, dy + origin_y));
            }
        }
    }
    for (std::int32_t radius = std::max(null_inner, search + 1);
         null_samples.size() < tuning::kMinimumNullSamples && radius <=
             std::max(null_inner, search + 1) + 2 * extent + 8;
         ++radius) {
        for (std::int32_t dy = -radius; dy <= radius; ++dy) {
            const std::int32_t step = std::abs(dy) == radius ? 1 : 2 * radius;
            for (std::int32_t dx = -radius; dx <= radius; dx += step) {
                null_samples.push_back(weighted_score(
                    component, weights, visible, width, height,
                    dx + origin_x, dy + origin_y));
            }
        }
    }
    if (null_samples.size() < tuning::kMinimumNullSamples) return false;
    std::sort(null_samples.begin(), null_samples.end());
    const double center = null_samples[null_samples.size() / 2U];
    std::vector<double> deviations(null_samples.size(), 0.0);
    std::transform(null_samples.begin(), null_samples.end(), deviations.begin(),
                   [center](const double value) { return std::abs(value - center); });
    std::sort(deviations.begin(), deviations.end());
    const double deviation = 1.4826 * deviations[deviations.size() / 2U];
    const float significance = deviation > 0.0
        ? static_cast<float>((best - center) / deviation)
        : std::numeric_limits<float>::max();
    if (significance < tuning::kMinimumSignificance) return false;
    const double signal = best - static_cast<double>(selection_bias(significance)) * deviation - center;
    if (!(signal > 0.0)) return false;
    const float gain = static_cast<float>(signal / square_sum);
    if (!std::isfinite(gain) || gain <= 0.0F) return false;
    confirmed = ConfirmedDefect{
        best_x + origin_x,
        best_y + origin_y,
        std::clamp(gain, 0.2F, 4.0F),
        significance};
    return true;
}

ConsensusOffset coarse_consensus_offset(
    const std::vector<RawComponent>& candidates,
    const std::span<const float> density,
    const std::span<const float> visible,
    const std::uint32_t width,
    const std::uint32_t height,
    const float magnitude_floor,
    const std::int32_t search) {
    std::vector<std::size_t> order(candidates.size(), 0U);
    std::iota(order.begin(), order.end(), 0U);
    std::sort(order.begin(), order.end(), [&](const std::size_t a, const std::size_t b) {
        return candidates[a].source_area > candidates[b].source_area;
    });
    std::vector<std::int32_t> votes_x{};
    std::vector<std::int32_t> votes_y{};
    const std::size_t vote_count = std::min<std::size_t>(64U, order.size());
    votes_x.reserve(vote_count);
    votes_y.reserve(vote_count);
    for (std::size_t ordinal = 0U; ordinal < vote_count; ++ordinal) {
        const RawComponent& candidate = candidates[order[ordinal]];
        const auto extent = static_cast<std::int32_t>(
            std::min(candidate.max_x - candidate.min_x,
                     candidate.max_y - candidate.min_y) / 2U + 1U);
        ConfirmedDefect vote{};
        if (confirm_component(candidate, density, visible, width, height,
                              magnitude_floor, search + extent, 0, 0, vote)) {
            votes_x.push_back(vote.offset_x);
            votes_y.push_back(vote.offset_y);
        }
    }
    if (votes_x.size() < 8U) return {};
    std::sort(votes_x.begin(), votes_x.end());
    std::sort(votes_y.begin(), votes_y.end());
    return ConsensusOffset{
        votes_x[votes_x.size() / 2U],
        votes_y[votes_y.size() / 2U]};
}

}  // namespace negaflow::imaging::infrared_detail
