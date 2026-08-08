#include "working_image_report.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <limits>

namespace negaflow::cli {
namespace {

void update_fingerprint(std::uint64_t& fingerprint, const float value) noexcept {
    const std::uint32_t bits = std::bit_cast<std::uint32_t>(value);
    for (std::uint32_t shift = 0U; shift < 32U; shift += 8U) {
        fingerprint ^= static_cast<std::uint8_t>((bits >> shift) & 0xffU);
        fingerprint *= 1'099'511'628'211ULL;
    }
}

}  // namespace

WorkingImageStatistics compute_working_image_statistics(
    const negaflow::imaging::WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
        return {};
    }
    const std::uint64_t required_pixels =
        (static_cast<std::uint64_t>(image.height - 1U) * image.stride_pixels) +
        image.width;
    if (required_pixels > image.pixels.size()) {
        return {};
    }

    WorkingImageStatistics statistics{
        true,
        {
            std::numeric_limits<float>::infinity(),
            std::numeric_limits<float>::infinity(),
            std::numeric_limits<float>::infinity(),
            std::numeric_limits<float>::infinity(),
        },
        {
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
        },
        14'695'981'039'346'656'037ULL,
    };
    for (std::uint32_t row = 0U; row < image.height; ++row) {
        const std::size_t row_offset =
            static_cast<std::size_t>(row) * image.stride_pixels;
        for (std::uint32_t column = 0U; column < image.width; ++column) {
            const negaflow::core::Rgba32F& pixel =
                image.pixels[row_offset + column];
            const std::array<float, 4> values{
                pixel.red,
                pixel.green,
                pixel.blue,
                pixel.alpha,
            };
            for (std::size_t channel = 0U; channel < values.size(); ++channel) {
                if (!std::isfinite(values[channel])) {
                    return {};
                }
                statistics.minimum[channel] =
                    std::min(statistics.minimum[channel], values[channel]);
                statistics.maximum[channel] =
                    std::max(statistics.maximum[channel], values[channel]);
                update_fingerprint(statistics.fingerprint_fnv1a64, values[channel]);
            }
        }
    }
    return statistics;
}

}  // namespace negaflow::cli
