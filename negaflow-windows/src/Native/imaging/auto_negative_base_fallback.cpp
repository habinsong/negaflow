#include "auto_negative_base_fallback.h"

#include "auto_negative_base_candidates.h"
#include "auto_negative_base_exclusion.h"

#include "bilinear_rgb_sampler.h"
#include "negaflow/imaging/mipmap_downsampler.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>

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

}  // namespace negaflow::imaging::auto_base_detail
