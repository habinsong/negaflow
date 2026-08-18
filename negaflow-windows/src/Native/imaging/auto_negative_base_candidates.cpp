#include "auto_negative_base_candidates.h"

#include "auto_negative_base_exclusion.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace negaflow::imaging::auto_base_detail {

using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;
using film_base_detail::SampleGridGeometry;
using film_base_detail::candidate_indices;
using film_base_detail::candidate_luma_peak;
using film_base_detail::coherent_measurement;
using film_base_detail::connected_component_base;
using film_base_detail::finite_rgb;
using film_base_detail::has_compatible_layout;
using film_base_detail::is_component_candidate;
using film_base_detail::luma_of;
using film_base_detail::make_sample_grid;
using film_base_detail::make_sample_grid_geometry;
using film_base_detail::median;
using film_base_detail::percentile;
using film_base_detail::upper_median;

[[nodiscard]] std::optional<BaseMeasurement> coherent_measurement(
    const SampleGrid& grid,
    const std::vector<std::size_t>& selected) {
    return coherent_measurement(grid.pixels, selected);
}

[[nodiscard]] std::optional<BaseMeasurement> continuous_border_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    std::vector<std::size_t> all = candidate_indices(grid, film_type, excluded);
    all.erase(std::remove_if(all.begin(), all.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), all.end());
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.height) * 0.06));
    std::vector<std::size_t> border;
    for (const std::size_t index : all) {
        const std::uint32_t x = static_cast<std::uint32_t>(index % grid.width);
        const std::uint32_t y = static_cast<std::uint32_t>(index / grid.width);
        if (x < edge_x || x >= grid.width - edge_x || y < edge_y || y >= grid.height - edge_y) {
            border.push_back(index);
        }
    }
    const std::vector<std::size_t>& candidates = border.size() >= 16U ? border : all;
    if (candidates.size() < 8U) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const double cut = percentile(lumas, 0.95);
    std::vector<std::size_t> bright;
    std::vector<std::size_t> row_counts(grid.height, 0U), column_counts(grid.width, 0U);
    for (const std::size_t index : candidates) {
        if (grid.lumas[index] < cut) { continue; }
        bright.push_back(index);
        ++row_counts[index / grid.width];
        ++column_counts[index % grid.width];
    }
    if (bright.size() < 4U) {
        return std::nullopt;
    }
    const std::size_t horizontal =
        static_cast<std::size_t>(static_cast<double>(grid.width) * 0.65);
    const std::size_t vertical =
        static_cast<std::size_t>(static_cast<double>(grid.height) * 0.65);
    bool continuous = false;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        continuous = continuous || ((y < edge_y || y >= grid.height - edge_y) && row_counts[y] >= horizontal);
    }
    for (std::uint32_t x = 0U; x < grid.width; ++x) {
        continuous = continuous || ((x < edge_x || x >= grid.width - edge_x) && column_counts[x] >= vertical);
    }
    return continuous ? coherent_measurement(grid, bright) : std::nullopt;
}

[[nodiscard]] std::optional<BaseMeasurement> distributed_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    std::vector<std::size_t> candidates = candidate_indices(grid, film_type, excluded);
    candidates.erase(std::remove_if(candidates.begin(), candidates.end(), [&grid, floor](const std::size_t index) {
        return grid.lumas[index] < floor;
    }), candidates.end());
    if (candidates.size() < 32U) {
        return std::nullopt;
    }
    std::vector<double> lumas;
    lumas.reserve(candidates.size());
    for (const std::size_t index : candidates) { lumas.push_back(grid.lumas[index]); }
    const double cut = percentile(lumas, 0.95);
    if (cut - median(lumas) < 0.02) {
        return std::nullopt;
    }
    std::vector<std::size_t> bright;
    for (const std::size_t index : candidates) {
        if (grid.lumas[index] >= cut) { bright.push_back(index); }
    }
    const std::size_t minimum = std::max<std::size_t>(32U, candidates.size() * 2U / 100U);
    return bright.size() >= minimum ? coherent_measurement(grid, bright) : std::nullopt;
}

}  // namespace negaflow::imaging::auto_base_detail
