#include "scanner_target_measure.h"

#include "scanner_target_color.h"
#include "scanner_target_profile.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace negaflow::imaging::scanner_target_detail {

[[nodiscard]] bool measure_inset(
    const negaflow::core::ImageView image,
    const double fraction,
    InsetStats& stats) {
    const std::uint32_t sample_width = std::min(160U, image.width);
    const std::uint32_t sample_height = std::max(
        1U, static_cast<std::uint32_t>(std::round(
            static_cast<double>(image.height) * sample_width / image.width)));
    const std::uint32_t inset_x = std::max(1U, static_cast<std::uint32_t>(sample_width * fraction));
    const std::uint32_t inset_y = std::max(1U, static_cast<std::uint32_t>(sample_height * fraction));
    std::vector<double> values;
    values.reserve(static_cast<std::size_t>(sample_width) * sample_height);
    for (std::uint32_t y = inset_y; y < std::max(inset_y + 1U, sample_height - inset_y); ++y) {
        const std::uint32_t source_y = std::min(
            image.height - 1U,
            static_cast<std::uint32_t>((static_cast<std::uint64_t>(y) * image.height) / sample_height));
        for (std::uint32_t x = inset_x; x < std::max(inset_x + 1U, sample_width - inset_x); ++x) {
            const std::uint32_t source_x = std::min(
                image.width - 1U,
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(x) * image.width) / sample_width));
            const auto pixel = image.pixels[
                static_cast<std::size_t>(source_y) * image.stride_pixels + source_x];
            values.push_back(luma({
                srgb_encode(clamp(pixel.red, 0.0, 1.0)),
                srgb_encode(clamp(pixel.green, 0.0, 1.0)),
                srgb_encode(clamp(pixel.blue, 0.0, 1.0)),
            }));
        }
    }
    if (values.size() < 64U) return false;
    auto copy = values;
    stats.median = percentile(copy, 0.50);
    copy = values;
    stats.p05 = percentile(copy, 0.05);
    copy = std::move(values);
    stats.p95 = percentile(copy, 0.95);
    return true;
}

[[nodiscard]] double scene_anchor_weight(
    const negaflow::core::ImageView image,
    double& median) {
    if (image.width <= 8U || image.height <= 8U) {
        median = 0.5;
        return 0.0;
    }
    InsetStats outer{};
    if (!measure_inset(image, 0.06, outer)) {
        median = 0.5;
        return 0.0;
    }
    InsetStats chosen = outer;
    InsetStats inner{};
    if (measure_inset(image, 0.15, inner) &&
        outer.p95 - inner.p95 < 0.05 &&
        inner.p05 - outer.p05 > 0.30) {
        chosen = inner;
    }
    median = chosen.median;
    return 1.0 - smoothstep(0.45, 0.66, chosen.p95 - chosen.p05);
}

}  // namespace negaflow::imaging::scanner_target_detail
