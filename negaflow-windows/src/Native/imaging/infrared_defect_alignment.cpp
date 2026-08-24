#include "infrared_defect_alignment.h"

#include "grain_mend_morphology.h"
#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <numeric>
#include <utility>
#include <vector>

namespace negaflow::imaging::infrared_detail {

std::optional<DefectAlignment> estimate_defect_alignment(
    const std::span<const float> infrared,
    const std::span<const float> red,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t search_radius) {
    if (search_radius == 0U || width <= 4U * search_radius || height <= 4U * search_radius) {
        return std::nullopt;
    }
    const std::uint32_t inset = std::max(search_radius + 2U, std::min(width, height) / 32U);
    if (width <= 2U * inset || height <= 2U * inset) return std::nullopt;
    std::vector<float> sample{};
    sample.reserve(static_cast<std::size_t>((width - 2U * inset) / 3U + 1U) *
                   ((height - 2U * inset) / 3U + 1U));
    for (std::uint32_t y = inset; y < height - inset; y += 3U) {
        for (std::uint32_t x = inset; x < width - inset; x += 3U) {
            sample.push_back(infrared[static_cast<std::size_t>(y) * width + x]);
        }
    }
    if (sample.size() <= 64U) return std::nullopt;
    const std::size_t base_index = static_cast<std::size_t>(
        0.90 * static_cast<double>(sample.size() - 1U));
    std::nth_element(sample.begin(), sample.begin() + base_index, sample.end());
    const float base = sample[base_index];
    const std::size_t median_index = sample.size() / 2U;
    std::nth_element(
        sample.begin(), sample.begin() + median_index, sample.begin() + base_index);
    const float median = sample[median_index];
    const float spread = base - median;
    if (!(base > 1.0e-4F) || !(spread > base * 1.0e-3F)) return std::nullopt;
    const float cut = base - 4.0F * spread;
    std::vector<std::size_t> points{};
    std::vector<float> weights{};
    for (std::uint32_t y = inset; y < height - inset; ++y) {
        for (std::uint32_t x = inset; x < width - inset; ++x) {
            const std::size_t pixel = static_cast<std::size_t>(y) * width + x;
            if (infrared[pixel] < cut) {
                points.push_back(pixel);
                weights.push_back((base - infrared[pixel]) / base);
            }
        }
    }
    if (points.size() < 16U) return std::nullopt;
    constexpr std::size_t kPointLimit = 20000U;
    if (points.size() > kPointLimit) {
        std::vector<std::size_t> order(points.size(), 0U);
        std::iota(order.begin(), order.end(), 0U);
        std::partial_sort(order.begin(), order.begin() + kPointLimit, order.end(),
            [&](const std::size_t a, const std::size_t b) { return weights[a] > weights[b]; });
        std::vector<std::size_t> limited_points{};
        std::vector<float> limited_weights{};
        limited_points.reserve(kPointLimit);
        limited_weights.reserve(kPointLimit);
        for (std::size_t ordinal = 0U; ordinal < kPointLimit; ++ordinal) {
            limited_points.push_back(points[order[ordinal]]);
            limited_weights.push_back(weights[order[ordinal]]);
        }
        points = std::move(limited_points);
        weights = std::move(limited_weights);
    }
    const std::uint32_t darkness_radius =
        std::max(4U, std::min(24U, std::min(width, height) / 200U));
    auto darkness = grain_mend_detail::box_mean(red, width, height, darkness_radius);
    negaflow::core::for_each_row_block(
        height,
        darkness.size() * 2U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            const std::size_t first = static_cast<std::size_t>(first_row) * width;
            const std::size_t end = static_cast<std::size_t>(first_row + row_count) * width;
            for (std::size_t index = first; index < end; ++index) {
                darkness[index] = std::max(0.0F, darkness[index] - red[index]);
            }
        });
    const double total_weight = std::accumulate(weights.begin(), weights.end(), 0.0);
    if (!(total_weight > 0.0)) return std::nullopt;
    const std::int32_t search = static_cast<std::int32_t>(search_radius);
    const std::int32_t side = 2 * search + 1;
    std::vector<double> scores(static_cast<std::size_t>(side) * side, 0.0);
    const auto score_work = static_cast<std::uint64_t>(scores.size()) >
            std::numeric_limits<std::uint64_t>::max() / points.size()
        ? std::numeric_limits<std::uint64_t>::max()
        : static_cast<std::uint64_t>(scores.size()) * points.size();
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(side),
        score_work,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                const std::int32_t dy = static_cast<std::int32_t>(row) - search;
                for (std::int32_t dx = -search; dx <= search; ++dx) {
                    double sum = 0.0;
                    for (std::size_t ordinal = 0U; ordinal < points.size(); ++ordinal) {
                        const std::size_t pixel = points[ordinal];
                        const std::int32_t x = static_cast<std::int32_t>(pixel % width) + dx;
                        const std::int32_t y = static_cast<std::int32_t>(pixel / width) + dy;
                        if (x >= 0 && y >= 0 && x < static_cast<std::int32_t>(width) &&
                            y < static_cast<std::int32_t>(height)) {
                            sum += static_cast<double>(darkness[static_cast<std::size_t>(y) * width +
                                static_cast<std::uint32_t>(x)]) * weights[ordinal];
                        }
                    }
                    const double score = sum / total_weight;
                    scores[static_cast<std::size_t>(dy + search) * side + dx + search] = score;
                }
            }
        });
    double best = -std::numeric_limits<double>::infinity();
    std::int32_t best_x = 0;
    std::int32_t best_y = 0;
    double score_sum = 0.0;
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            const double score =
                scores[static_cast<std::size_t>(dy + search) * side + dx + search];
            score_sum += score;
            if (score > best) {
                best = score;
                best_x = dx;
                best_y = dy;
            }
        }
    }
    if (!(best > 0.0)) return std::nullopt;
    double runner_up = -std::numeric_limits<double>::infinity();
    for (std::int32_t dy = -search; dy <= search; ++dy) {
        for (std::int32_t dx = -search; dx <= search; ++dx) {
            if (std::abs(dx - best_x) <= 2 && std::abs(dy - best_y) <= 2) continue;
            runner_up = std::max(runner_up,
                scores[static_cast<std::size_t>(dy + search) * side + dx + search]);
        }
    }
    const double mean = score_sum / static_cast<double>(scores.size());
    if (!(mean > 0.0) || best < mean * 1.10) return std::nullopt;
    return DefectAlignment{
        -best_x,
        -best_y,
        best,
        std::isfinite(runner_up) ? runner_up : 0.0,
        std::abs(best_x) == search || std::abs(best_y) == search};
}

}  // namespace negaflow::imaging::infrared_detail
