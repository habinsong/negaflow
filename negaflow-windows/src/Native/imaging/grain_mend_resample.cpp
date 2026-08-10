#include "grain_mend_resample.h"

#include "negaflow/color/srgb_transfer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {
namespace {

constexpr double lanczos_radius = 3.0;
constexpr double pi = 3.141592653589793238462643383279502884;

struct AxisSpan final {
    std::size_t first{0U};
    std::size_t count{0U};
};

struct AxisKernel final {
    std::vector<AxisSpan> spans{};
    std::vector<std::uint32_t> sources{};
    std::vector<float> weights{};
};

struct CachedRow final {
    std::uint32_t source_y{0U};
    std::array<std::vector<float>, 3U> channels{};
};

[[nodiscard]] double sinc(const double value) noexcept {
    if (std::abs(value) <= std::numeric_limits<double>::epsilon()) {
        return 1.0;
    }
    const double angle = pi * value;
    return std::sin(angle) / angle;
}

[[nodiscard]] double lanczos(const double value) noexcept {
    const double magnitude = std::abs(value);
    if (magnitude >= lanczos_radius) {
        return 0.0;
    }
    return sinc(value) * sinc(value / lanczos_radius);
}

[[nodiscard]] AxisKernel make_axis_kernel(
    const std::uint32_t source_size,
    const std::uint32_t output_size,
    const double uniform_scale) {
    AxisKernel result{};
    result.spans.reserve(output_size);
    const double filter_scale = std::min(1.0, uniform_scale);
    const double support = lanczos_radius / filter_scale;

    for (std::uint32_t output = 0U; output < output_size; ++output) {
        const double center =
            (static_cast<double>(output) + 0.5) / uniform_scale - 0.5;
        const std::int64_t first = static_cast<std::int64_t>(
            std::ceil(center - support));
        const std::int64_t last = static_cast<std::int64_t>(
            std::floor(center + support));
        const std::size_t offset = result.sources.size();
        double weight_sum = 0.0;
        for (std::int64_t source = first; source <= last; ++source) {
            const double weight = lanczos((center - static_cast<double>(source)) *
                                          filter_scale);
            if (weight == 0.0) {
                continue;
            }
            const std::int64_t clamped = std::clamp<std::int64_t>(
                source, 0, static_cast<std::int64_t>(source_size) - 1);
            result.sources.push_back(static_cast<std::uint32_t>(clamped));
            result.weights.push_back(static_cast<float>(weight));
            weight_sum += weight;
        }

        const std::size_t count = result.sources.size() - offset;
        if (count == 0U || std::abs(weight_sum) <=
                               std::numeric_limits<double>::epsilon()) {
            const std::uint32_t nearest = static_cast<std::uint32_t>(
                std::clamp<std::int64_t>(
                    static_cast<std::int64_t>(std::llround(center)),
                    0,
                    static_cast<std::int64_t>(source_size) - 1));
            result.sources.resize(offset);
            result.weights.resize(offset);
            result.sources.push_back(nearest);
            result.weights.push_back(1.0F);
            result.spans.push_back({offset, 1U});
            continue;
        }

        const double inverse = 1.0 / weight_sum;
        for (std::size_t index = offset; index < offset + count; ++index) {
            result.weights[index] = static_cast<float>(
                static_cast<double>(result.weights[index]) * inverse);
        }
        result.spans.push_back({offset, count});
    }
    return result;
}

[[nodiscard]] CachedRow make_horizontal_row(
    const WorkingImage& image,
    const std::uint32_t source_y,
    const AxisKernel& horizontal,
    const std::uint32_t output_width) {
    CachedRow result{};
    result.source_y = source_y;
    for (auto& channel : result.channels) {
        channel.resize(output_width);
    }
    const auto* const source_row = image.pixels.data() +
        static_cast<std::size_t>(source_y) * image.stride_pixels;
    for (std::uint32_t output_x = 0U; output_x < output_width; ++output_x) {
        const AxisSpan span = horizontal.spans[output_x];
        std::array<double, 3U> sums{};
        for (std::size_t tap = 0U; tap < span.count; ++tap) {
            const std::size_t kernel_index = span.first + tap;
            const auto pixel = source_row[horizontal.sources[kernel_index]];
            const double weight = horizontal.weights[kernel_index];
            sums[0] += static_cast<double>(pixel.red) * weight;
            sums[1] += static_cast<double>(pixel.green) * weight;
            sums[2] += static_cast<double>(pixel.blue) * weight;
        }
        for (std::size_t channel = 0U; channel < result.channels.size(); ++channel) {
            result.channels[channel][output_x] = static_cast<float>(sums[channel]);
        }
    }
    return result;
}

[[nodiscard]] const CachedRow& cached_horizontal_row(
    std::vector<CachedRow>& cache,
    const WorkingImage& image,
    const std::uint32_t source_y,
    const AxisKernel& horizontal,
    const std::uint32_t output_width) {
    const auto found = std::find_if(
        cache.begin(),
        cache.end(),
        [&](const CachedRow& row) { return row.source_y == source_y; });
    if (found != cache.end()) {
        return *found;
    }
    cache.push_back(make_horizontal_row(
        image, source_y, horizontal, output_width));
    return cache.back();
}

[[nodiscard]] float mask_value(
    const std::vector<std::uint8_t>& mask,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int64_t x,
    const std::int64_t y) noexcept {
    if (x < 0 || y < 0 || x >= static_cast<std::int64_t>(width) ||
        y >= static_cast<std::int64_t>(height)) {
        return 0.0F;
    }
    return mask[static_cast<std::size_t>(y) * width +
                static_cast<std::size_t>(x)] != 0U
        ? 1.0F
        : 0.0F;
}

}  // namespace

void render_detection_rgb(
    const WorkingImage& image,
    const std::uint32_t output_width,
    const std::uint32_t output_height,
    std::array<std::vector<float>, 3U>& channels) {
    if (output_width == 0U || output_height == 0U ||
        output_width > image.width || output_height > image.height) {
        throw std::bad_alloc{};
    }
    const std::size_t output_count =
        static_cast<std::size_t>(output_width) * output_height;
    for (auto& channel : channels) {
        channel.resize(output_count);
    }

    if (output_width == image.width && output_height == image.height) {
        for (std::uint32_t y = 0U; y < output_height; ++y) {
            const auto* const row = image.pixels.data() +
                static_cast<std::size_t>(y) * image.stride_pixels;
            for (std::uint32_t x = 0U; x < output_width; ++x) {
                const std::size_t index =
                    static_cast<std::size_t>(y) * output_width + x;
                channels[0][index] = negaflow::color::linear_to_srgb_encoded(
                    row[x].red);
                channels[1][index] = negaflow::color::linear_to_srgb_encoded(
                    row[x].green);
                channels[2][index] = negaflow::color::linear_to_srgb_encoded(
                    row[x].blue);
            }
        }
        return;
    }

    const double uniform_scale = image.width >= image.height
        ? static_cast<double>(output_width) / static_cast<double>(image.width)
        : static_cast<double>(output_height) / static_cast<double>(image.height);
    const AxisKernel horizontal =
        make_axis_kernel(image.width, output_width, uniform_scale);
    const AxisKernel vertical =
        make_axis_kernel(image.height, output_height, uniform_scale);
    std::vector<CachedRow> cache{};
    std::size_t maximum_vertical_taps = 0U;
    for (const AxisSpan span : vertical.spans) {
        maximum_vertical_taps = std::max(maximum_vertical_taps, span.count);
    }
    cache.reserve(maximum_vertical_taps);
    std::vector<const CachedRow*> vertical_rows{};
    vertical_rows.reserve(maximum_vertical_taps);

    for (std::uint32_t output_y = 0U; output_y < output_height; ++output_y) {
        const AxisSpan vertical_span = vertical.spans[output_y];
        std::uint32_t minimum_source_y = image.height - 1U;
        for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
            minimum_source_y = std::min(
                minimum_source_y,
                vertical.sources[vertical_span.first + tap]);
        }
        cache.erase(
            std::remove_if(
                cache.begin(),
                cache.end(),
                [&](const CachedRow& row) {
                    return row.source_y < minimum_source_y;
                }),
            cache.end());
        for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
            const std::uint32_t source_y =
                vertical.sources[vertical_span.first + tap];
            (void)cached_horizontal_row(
                cache, image, source_y, horizontal, output_width);
        }
        vertical_rows.clear();
        for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
            const std::uint32_t source_y =
                vertical.sources[vertical_span.first + tap];
            vertical_rows.push_back(&cached_horizontal_row(
                cache, image, source_y, horizontal, output_width));
        }

        for (std::uint32_t output_x = 0U; output_x < output_width; ++output_x) {
            std::array<double, 3U> sums{};
            for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
                const std::size_t kernel_index = vertical_span.first + tap;
                const double weight = vertical.weights[kernel_index];
                for (std::size_t channel = 0U; channel < sums.size(); ++channel) {
                    sums[channel] +=
                        static_cast<double>(
                            vertical_rows[tap]->channels[channel][output_x]) *
                        weight;
                }
            }
            const std::size_t output_index =
                static_cast<std::size_t>(output_y) * output_width + output_x;
            for (std::size_t channel = 0U; channel < channels.size(); ++channel) {
                channels[channel][output_index] =
                    negaflow::color::linear_to_srgb_encoded(
                        static_cast<float>(sums[channel]));
            }
        }
    }
}

float sample_transformed_mask(
    const std::vector<std::uint8_t>& mask,
    const std::uint32_t mask_width,
    const std::uint32_t mask_height,
    const std::uint32_t output_width,
    const std::uint32_t output_height,
    const std::uint32_t output_x,
    const std::uint32_t output_y) noexcept {
    if (mask_width == output_width && mask_height == output_height) {
        return mask[static_cast<std::size_t>(output_y) * mask_width + output_x] != 0U
            ? 1.0F
            : 0.0F;
    }

    const double source_x =
        (static_cast<double>(output_x) + 0.5) *
            static_cast<double>(mask_width) / static_cast<double>(output_width) -
        0.5;
    const double source_y =
        (static_cast<double>(output_y) + 0.5) *
            static_cast<double>(mask_height) / static_cast<double>(output_height) -
        0.5;
    const std::int64_t x0 = static_cast<std::int64_t>(std::floor(source_x));
    const std::int64_t y0 = static_cast<std::int64_t>(std::floor(source_y));
    const float fraction_x = static_cast<float>(source_x - static_cast<double>(x0));
    const float fraction_y = static_cast<float>(source_y - static_cast<double>(y0));
    const float top =
        mask_value(mask, mask_width, mask_height, x0, y0) * (1.0F - fraction_x) +
        mask_value(mask, mask_width, mask_height, x0 + 1, y0) * fraction_x;
    const float bottom =
        mask_value(mask, mask_width, mask_height, x0, y0 + 1) * (1.0F - fraction_x) +
        mask_value(mask, mask_width, mask_height, x0 + 1, y0 + 1) * fraction_x;
    return std::clamp(
        top * (1.0F - fraction_y) + bottom * fraction_y,
        0.0F,
        1.0F);
}

}  // namespace negaflow::imaging::grain_mend_detail
