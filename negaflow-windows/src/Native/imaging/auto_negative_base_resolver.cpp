#include "negaflow/imaging/auto_negative_base_resolver.h"

#include "negaflow/imaging/mipmap_downsampler.h"

#include "bilinear_rgb_sampler.h"
#include "film_base_sampling.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <optional>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr std::array<float, 3> color_fallback{0.86F, 0.68F, 0.50F};
constexpr std::array<float, 3> monochrome_fallback{0.80F, 0.80F, 0.80F};
using film_base_detail::BaseMeasurement;
using film_base_detail::SampleGrid;
using film_base_detail::SampleGridGeometry;
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
using film_base_detail::candidate_indices;
using film_base_detail::upper_median;

[[nodiscard]] std::array<float, 3> fallback_for(const NegativeFilmType film_type) noexcept {
    return film_type == NegativeFilmType::black_and_white ? monochrome_fallback : color_fallback;
}

[[nodiscard]] std::array<float, 3> narrow_measurement(const BaseMeasurement& measurement) noexcept {
    return {
        static_cast<float>(measurement[0]),
        static_cast<float>(measurement[1]),
        static_cast<float>(measurement[2]),
    };
}




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

[[nodiscard]] std::optional<BaseMeasurement> strip_fallback_base(
    const SampleGrid& grid,
    const NegativeFilmType film_type,
    const std::vector<bool>* excluded) {
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(grid.height) * 0.06));
    const auto strip_mean = [&grid, excluded](const auto contains) -> std::optional<BaseMeasurement> {
        std::array<double, 3> total{};
        std::size_t count = 0U;
        for (std::uint32_t y = 0U; y < grid.height; ++y) {
            for (std::uint32_t x = 0U; x < grid.width; ++x) {
                const std::size_t index = static_cast<std::size_t>(y) * grid.width + x;
                if (!contains(x, y) || (excluded != nullptr && (*excluded)[index])) { continue; }
                total[0] += grid.pixels[index].red;
                total[1] += grid.pixels[index].green;
                total[2] += grid.pixels[index].blue;
                ++count;
            }
        }
        if (count == 0U) { return std::nullopt; }
        const double inverse = 1.0 / static_cast<double>(count);
        return BaseMeasurement{
            total[0] * inverse,
            total[1] * inverse,
            total[2] * inverse};
    };
    std::vector<BaseMeasurement> strips;
    for (const auto& mean : {
             strip_mean([edge_y](const std::uint32_t, const std::uint32_t y) { return y < edge_y; }),
             strip_mean([&grid, edge_y](const std::uint32_t, const std::uint32_t y) { return y >= grid.height - edge_y; }),
             strip_mean([edge_x](const std::uint32_t x, const std::uint32_t) { return x < edge_x; }),
             strip_mean([&grid, edge_x](const std::uint32_t x, const std::uint32_t) { return x >= grid.width - edge_x; })}) {
        if (mean.has_value()) { strips.push_back(*mean); }
    }
    if (strips.empty()) { return std::nullopt; }
    const auto strip_luma = [](const BaseMeasurement& strip) noexcept {
        return (strip[0] + strip[1] + strip[2]) / 3.0;
    };
    double brightest = 0.0;
    for (const auto& strip : strips) {
        const double luma = strip_luma(strip);
        if (luma < 0.97) { brightest = std::max(brightest, luma); }
    }
    if (brightest <= 0.0) { return std::nullopt; }
    const double base_level = candidate_luma_peak(grid, film_type);
    std::vector<double> red, green, blue;
    for (const auto& strip : strips) {
        const double luma = strip_luma(strip);
        if (luma >= brightest * 0.55 && luma >= base_level * 0.50) {
            red.push_back(strip[0]); green.push_back(strip[1]); blue.push_back(strip[2]);
        }
    }
    if (red.empty()) { return std::nullopt; }
    return BaseMeasurement{
        std::clamp(
            median(std::move(red)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(green)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin)),
        std::clamp(
            median(std::move(blue)),
            static_cast<double>(minimum_manual_dmin),
            static_cast<double>(maximum_manual_dmin))};
}

[[nodiscard]] std::optional<BaseMeasurement> scene_edge_fallback_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) {
    const std::optional<SampleGridGeometry> geometry =
        make_sample_grid_geometry(image, 64U, 320U);
    if (!geometry.has_value()) {
        return std::nullopt;
    }
    const std::uint32_t edge_x = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(geometry->width) * 0.06));
    const std::uint32_t edge_y = std::max(
        1U, static_cast<std::uint32_t>(static_cast<double>(geometry->height) * 0.06));

    std::vector<negaflow::core::Rgba32F> edge_pixels;
    edge_pixels.reserve(static_cast<std::size_t>(geometry->width) * edge_y * 2U +
                        static_cast<std::size_t>(geometry->height) * edge_x * 2U);
    const negaflow::core::ConstImageView source{
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
    for (std::uint32_t y = 0U; y < geometry->height; ++y) {
        const double source_y =
            (static_cast<double>(y) + 0.5) / geometry->uniform_scale - 0.5;
        for (std::uint32_t x = 0U; x < geometry->width; ++x) {
            if (x >= edge_x && x < geometry->width - edge_x &&
                y >= edge_y && y < geometry->height - edge_y) {
                continue;
            }
            const double source_x =
                (static_cast<double>(x) + 0.5) / geometry->uniform_scale - 0.5;
            const detail::BilinearRgb sampled =
                detail::sample_bilinear_rgb_transparent(source, source_x, source_y);
            edge_pixels.push_back({
                static_cast<float>(sampled.red),
                static_cast<float>(sampled.green),
                static_cast<float>(sampled.blue),
                1.0F,
            });
        }
    }

    std::vector<double> edge_lumas;
    edge_lumas.reserve(edge_pixels.size());
    for (const negaflow::core::Rgba32F& pixel : edge_pixels) {
        const double luma = luma_of(pixel);
        if (std::isfinite(luma) && luma < 0.92) {
            edge_lumas.push_back(luma);
        }
    }
    if (edge_lumas.empty()) {
        return std::nullopt;
    }
    const double edge_peak = percentile(edge_lumas, 0.99);
    const double luma_floor = std::max(0.02, edge_peak * 0.45);
    std::vector<double> red;
    std::vector<double> green;
    std::vector<double> blue;
    red.reserve(edge_pixels.size());
    green.reserve(edge_pixels.size());
    blue.reserve(edge_pixels.size());
    for (const negaflow::core::Rgba32F& pixel : edge_pixels) {
        if (!finite_rgb(pixel)) {
            continue;
        }
        const double luma = luma_of(pixel);
        if (luma < luma_floor || luma >= 0.92) {
            continue;
        }
        const double red_value = static_cast<double>(pixel.red);
        const double green_value = static_cast<double>(pixel.green);
        const double blue_value = static_cast<double>(pixel.blue);
        const double peak = std::max(red_value, std::max(green_value, blue_value));
        if (film_type == NegativeFilmType::black_and_white) {
            const double tolerance = peak * 0.12 + 0.01;
            if (std::abs(red_value - green_value) > tolerance ||
                std::abs(green_value - blue_value) > tolerance) {
                continue;
            }
        } else if (red_value < green_value - 0.01 ||
                   green_value < blue_value - 0.01 || peak <= 0.0 ||
                   red_value - blue_value < std::max(0.003, peak * 0.10)) {
            continue;
        }
        red.push_back(red_value);
        green.push_back(green_value);
        blue.push_back(blue_value);
    }
    if (red.size() < 32U) {
        return std::nullopt;
    }
    return BaseMeasurement{
        percentile(red, 0.90), percentile(green, 0.90), percentile(blue, 0.90)};
}

}  // namespace

AutoNegativeBaseResult resolve_auto_negative_base(
    const WorkingImage& image,
    const NegativeFilmType film_type) noexcept {
    AutoNegativeBaseResult result{};
    if (!has_compatible_layout(image)) {
        return result;
    }

    result.status = AutoNegativeBaseStatus::ok;
    result.dmin = fallback_for(film_type);
    const auto with_chromogenic_fallback = [&image, film_type](const AutoNegativeBaseResult resolved) {
        if (film_type != NegativeFilmType::black_and_white ||
            resolved.status != AutoNegativeBaseStatus::ok) {
            return resolved;
        }
        const double maximum = std::max(
            static_cast<double>(resolved.dmin[0]),
            std::max(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        const double minimum = std::min(
            static_cast<double>(resolved.dmin[0]),
            std::min(
                static_cast<double>(resolved.dmin[1]),
                static_cast<double>(resolved.dmin[2])));
        // macOS's estimator returns nil when neutral-base measurement fails.  Its
        // fallback constant is applied only after the chromogenic retry, so the
        // Windows fallback must not be mistaken for a measured neutral base here.
        if (resolved.source != AutoNegativeBaseSource::fallback &&
            (minimum <= 1.0e-6 || maximum / minimum <= 1.25)) {
            return resolved;
        }
        const AutoNegativeBaseResult chromogenic = resolve_auto_negative_base(image, NegativeFilmType::color);
        return chromogenic.status == AutoNegativeBaseStatus::ok &&
                chromogenic.source != AutoNegativeBaseSource::fallback
            ? chromogenic
            : resolved;
    };
    if (image.width <= 4U || image.height <= 4U) {
        return result;
    }

    try {
        const std::optional<SampleGrid> grid = make_sample_grid(image);
        if (!grid.has_value()) {
            return result;
        }
        if (const std::optional<BaseMeasurement> component =
                connected_component_base(*grid, film_type)) {
            result.dmin = narrow_measurement(*component);
            result.source = AutoNegativeBaseSource::connected_component;
            return with_chromogenic_fallback(result);
        }
        const std::optional<std::vector<bool>> exclusion = non_film_exclusion(*grid, film_type);
        const std::vector<bool>* excluded = exclusion.has_value() ? &*exclusion : nullptr;
        const std::optional<BaseMeasurement> edge =
            continuous_border_base(*grid, film_type, excluded);
        const std::optional<BaseMeasurement> distributed =
            distributed_base(*grid, film_type, excluded);
        if (edge.has_value() && distributed.has_value()) {
            const double edge_luma = ((*edge)[0] + (*edge)[1] + (*edge)[2]) / 3.0;
            const double distributed_luma =
                ((*distributed)[0] + (*distributed)[1] + (*distributed)[2]) / 3.0;
            const bool use_edge = edge_luma >= distributed_luma * 0.85;
            result.dmin = narrow_measurement(use_edge ? *edge : *distributed);
            result.source = use_edge
                ? AutoNegativeBaseSource::continuous_border
                : AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (edge.has_value()) {
            result.dmin = narrow_measurement(*edge);
            result.source = AutoNegativeBaseSource::continuous_border;
            return with_chromogenic_fallback(result);
        }
        if (distributed.has_value()) {
            result.dmin = narrow_measurement(*distributed);
            result.source = AutoNegativeBaseSource::distributed_mask;
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> strip =
                strip_fallback_base(*grid, film_type, excluded)) {
            result.dmin = narrow_measurement(*strip);
            result.source = AutoNegativeBaseSource::strip_fallback;
            return with_chromogenic_fallback(result);
        }
        if (const std::optional<BaseMeasurement> scene_edge =
                scene_edge_fallback_base(image, film_type)) {
            result.dmin = narrow_measurement(*scene_edge);
            result.source = AutoNegativeBaseSource::scene_edge;
        }
    } catch (...) {
        // The documented fallback is preferable to allowing an allocation failure to cross a
        // noexcept ABI boundary. It remains distinguishable from a manual base in request mode.
    }
    return with_chromogenic_fallback(result);
}

const char* auto_negative_base_status_name(const AutoNegativeBaseStatus status) noexcept {
    switch (status) {
        case AutoNegativeBaseStatus::ok:
            return "ok";
        case AutoNegativeBaseStatus::invalid_image:
            return "invalid_image";
    }
    return "unknown_auto_negative_base_status";
}

}  // namespace negaflow::imaging
