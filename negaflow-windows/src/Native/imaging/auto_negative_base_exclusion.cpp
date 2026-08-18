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

[[nodiscard]] std::vector<bool> dilate(
    const std::vector<bool>& selected,
    const SampleGrid& grid) {
    std::vector<bool> result = selected;
    for (std::uint32_t y = 0U; y < grid.height; ++y) {
        for (std::uint32_t x = 0U; x < grid.width; ++x) {
            if (!selected[static_cast<std::size_t>(y) * grid.width + x]) {
                continue;
            }
            for (std::uint32_t ny = y > 2U ? y - 2U : 0U;
                 ny <= std::min(grid.height - 1U, y + 2U); ++ny) {
                for (std::uint32_t nx = x > 2U ? x - 2U : 0U;
                     nx <= std::min(grid.width - 1U, x + 2U); ++nx) {
                    result[static_cast<std::size_t>(ny) * grid.width + nx] = true;
                }
            }
        }
    }
    return result;
}

[[nodiscard]] std::optional<double> brightest_coherent_mode(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    std::vector<std::size_t> candidates = candidate_indices(grid, film_type);
    const double floor = candidate_luma_peak(grid, film_type) * 0.10;
    candidates.erase(
        std::remove_if(
            candidates.begin(),
            candidates.end(),
            [&grid, floor](const std::size_t index) {
                return grid.lumas[index] < floor;
            }),
        candidates.end());
    if (candidates.empty()) {
        return std::nullopt;
    }
    std::vector<std::size_t> sorted = candidates;
    std::sort(sorted.begin(), sorted.end(), [&grid](const std::size_t left, const std::size_t right) {
        return grid.lumas[left] > grid.lumas[right];
    });
    const std::size_t coherent_count = std::max<std::size_t>(24U, grid.pixels.size() * 4U / 1000U);
    const auto mode_center = [&grid, &sorted, coherent_count](const double upper) -> std::optional<double> {
        std::size_t low = 0U;
        std::size_t high = 0U;
        for (std::size_t index = 0U; index < sorted.size(); ++index) {
            const double center = grid.lumas[sorted[index]];
            if (center >= upper) {
                continue;
            }
            while (low < sorted.size() && grid.lumas[sorted[low]] > center + 0.03) {
                ++low;
            }
            high = std::max(high, low);
            while (high < sorted.size() && grid.lumas[sorted[high]] >= center - 0.03) {
                ++high;
            }
            if (high - low >= coherent_count) {
                return center;
            }
        }
        return std::nullopt;
    };
    const std::optional<double> top = mode_center(std::numeric_limits<double>::infinity());
    if (!top.has_value() || film_type == NegativeFilmType::black_and_white || *top < 0.60) {
        return top;
    }
    const std::optional<double> second = mode_center(*top * 0.87);
    if (!second.has_value() || *second / *top < 0.12 || *second / *top > 0.87) {
        return top;
    }
    const double gap_low = *second + 0.045;
    const double gap_high = *top - 0.045;
    if (gap_high <= gap_low) {
        return top;
    }
    std::vector<bool> top_cells(grid.pixels.size(), false);
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        top_cells[index] = grid.lumas[index] >= gap_high;
    }
    const std::vector<bool> halo = dilate(top_cells, grid);
    std::size_t gap_count = 0U;
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        if (grid.lumas[index] > gap_low && grid.lumas[index] < gap_high && !halo[index]) {
            ++gap_count;
        }
    }
    if (static_cast<double>(gap_count) > static_cast<double>(grid.pixels.size()) * 0.002) {
        return top;
    }
    const auto median_red_minus_blue = [&grid, &sorted](const double center) {
        std::vector<double> values;
        for (const std::size_t index : sorted) {
            if (std::abs(grid.lumas[index] - center) <= 0.03) {
                values.push_back(
                    static_cast<double>(grid.pixels[index].red) -
                    static_cast<double>(grid.pixels[index].blue));
            }
        }
        return upper_median(std::move(values));
    };
    return median_red_minus_blue(*top) < median_red_minus_blue(*second) * 0.75 ? second : top;
}

[[nodiscard]] std::optional<std::vector<bool>> non_film_exclusion(
    const SampleGrid& grid,
    const NegativeFilmType film_type) {
    const std::optional<double> base_mode = brightest_coherent_mode(grid, film_type);
    const double cut = std::min(0.88, base_mode.has_value() ? *base_mode * 1.12 : 0.88);
    std::vector<bool> bright(grid.pixels.size(), false);
    bool has_bright = false;
    for (std::size_t index = 0U; index < grid.pixels.size(); ++index) {
        if (grid.lumas[index] >= cut) {
            bright[index] = true;
            has_bright = true;
        }
    }
    if (!has_bright) {
        return std::nullopt;
    }
    std::vector<bool> excluded = dilate(bright, grid);
    if (candidate_indices(grid, film_type, &excluded).size() < 24U) {
        return std::nullopt;
    }
    return excluded;
}

}  // namespace negaflow::imaging::auto_base_detail
