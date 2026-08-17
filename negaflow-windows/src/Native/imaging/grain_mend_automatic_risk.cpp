#include "grain_mend_automatic_risk.h"

#include <algorithm>
#include <limits>

namespace negaflow::imaging::grain_mend_detail {
namespace {

/// macOS `maximumLocalCandidateDensity` — 후보가 가장 몰린 국소 타일의 밀도입니다. 경고
/// 판정 입력이며 성분을 거르지 않습니다. 짧은 변이 1,024 미만이면 재지 않습니다(작은
/// 프레임에서는 타일 하나가 프레임의 상당 부분이라 밀도가 의미를 잃습니다).
[[nodiscard]] double maximum_local_candidate_density(
    const std::vector<ClassifiedComponent>& components,
    const std::uint32_t width,
    const std::uint32_t height) {
    if (components.empty() ||
        std::min(width, height) < whole_frame_automatic_minimum_short_side) {
        return 0.0;
    }
    const std::uint32_t tile_side = std::max(
        whole_frame_automatic_minimum_tile_side,
        std::max(width, height) / whole_frame_automatic_tile_divisor);
    const std::uint32_t columns = (width + tile_side - 1U) / tile_side;
    const std::uint32_t rows = (height + tile_side - 1U) / tile_side;
    const std::size_t tile_count =
        static_cast<std::size_t>(columns) * static_cast<std::size_t>(rows);
    if (tile_count == 0U) {
        return 0.0;
    }
    std::vector<std::size_t> counts(tile_count, 0U);
    const std::size_t pixel_count =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    for (const ClassifiedComponent& component : components) {
        for (const std::size_t pixel : component.pixels) {
            if (pixel >= pixel_count) {
                continue;
            }
            const std::uint32_t y = static_cast<std::uint32_t>(pixel / width);
            const std::uint32_t x = static_cast<std::uint32_t>(pixel % width);
            ++counts[static_cast<std::size_t>(y / tile_side) * columns +
                     (x / tile_side)];
        }
    }
    double maximum = 0.0;
    for (std::uint32_t row = 0U; row < rows; ++row) {
        const std::uint32_t tile_height = std::min(
            tile_side, height - row * tile_side);
        for (std::uint32_t column = 0U; column < columns; ++column) {
            const std::uint32_t tile_width = std::min(
                tile_side, width - column * tile_side);
            const double density = static_cast<double>(
                    counts[static_cast<std::size_t>(row) * columns + column]) /
                (static_cast<double>(tile_width) *
                 static_cast<double>(tile_height));
            maximum = std::max(maximum, density);
        }
    }
    return maximum;
}

}  // namespace

AutomaticRisk measure_automatic_risk(
    const std::vector<ClassifiedComponent>& components,
    const std::uint32_t width,
    const std::uint32_t height) {
    AutomaticRisk risk{};
    const std::size_t area =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    if (area == 0U) {
        return risk;
    }
    // Swift `reduce(into:)` 와 같은 자리입니다 — 더하기가 넘치면 그 자리에서 area 로
    // 포화시킵니다(비율이 1 을 넘지 않게).
    std::size_t candidate_pixels = 0U;
    for (const ClassifiedComponent& component : components) {
        const std::size_t addition = candidate_pixels + component.pixels.size();
        candidate_pixels = addition < candidate_pixels ? area : addition;
    }
    risk.candidate_pixel_fraction = static_cast<double>(candidate_pixels) /
        static_cast<double>(area);
    const double fraction_limit = std::max(
        whole_frame_automatic_candidate_fraction_limit,
        whole_frame_automatic_minimum_candidate_pixels /
            static_cast<double>(area));
    risk.false_positive_risk =
        risk.candidate_pixel_fraction > fraction_limit ||
        maximum_local_candidate_density(components, width, height) >
            whole_frame_automatic_local_density_limit;
    return risk;
}

}  // namespace negaflow::imaging::grain_mend_detail
