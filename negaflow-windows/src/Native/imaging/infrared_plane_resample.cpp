#include "negaflow/imaging/infrared_plane_resample.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace negaflow::imaging {
namespace {

[[nodiscard]] float sample_or_transparent(
    const std::span<const float> source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int64_t x,
    const std::int64_t y) noexcept {
    if (x < 0 || y < 0 ||
        x >= static_cast<std::int64_t>(width) ||
        y >= static_cast<std::int64_t>(height)) {
        return 0.0F;
    }
    return source[static_cast<std::size_t>(y) * width +
                  static_cast<std::size_t>(x)];
}

}  // namespace

bool resample_infrared_plane_to_extent(
    const std::span<const float> source,
    const std::uint32_t source_width,
    const std::uint32_t source_height,
    const std::uint32_t output_width,
    const std::uint32_t output_height,
    std::vector<float>& output) {
    if (source_width <= 1U || source_height <= 1U ||
        output_width == 0U || output_height == 0U ||
        source_width > std::numeric_limits<std::size_t>::max() / source_height ||
        source.size() != static_cast<std::size_t>(source_width) * source_height ||
        output_width > std::numeric_limits<std::size_t>::max() / output_height) {
        return false;
    }
    output.resize(static_cast<std::size_t>(output_width) * output_height);
    for (std::uint32_t y = 0U; y < output_height; ++y) {
        const double source_y =
            (static_cast<double>(y) + 0.5) * source_height / output_height - 0.5;
        const auto y0 = static_cast<std::int64_t>(std::floor(source_y));
        const double ty = source_y - static_cast<double>(y0);
        for (std::uint32_t x = 0U; x < output_width; ++x) {
            const double source_x =
                (static_cast<double>(x) + 0.5) * source_width / output_width - 0.5;
            const auto x0 = static_cast<std::int64_t>(std::floor(source_x));
            const double tx = source_x - static_cast<double>(x0);
            const double top = sample_or_transparent(
                source, source_width, source_height, x0, y0) * (1.0 - tx) +
                sample_or_transparent(
                    source, source_width, source_height, x0 + 1, y0) * tx;
            const double bottom = sample_or_transparent(
                source, source_width, source_height, x0, y0 + 1) * (1.0 - tx) +
                sample_or_transparent(
                    source, source_width, source_height, x0 + 1, y0 + 1) * tx;
            output[static_cast<std::size_t>(y) * output_width + x] =
                static_cast<float>(top * (1.0 - ty) + bottom * ty);
        }
    }
    return true;
}

}  // namespace negaflow::imaging
