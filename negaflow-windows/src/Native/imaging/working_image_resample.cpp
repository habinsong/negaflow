#include "negaflow/imaging/working_image_resample.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging {
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
    std::vector<negaflow::core::Rgba32F> pixels{};
};

[[nodiscard]] bool checked_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height,
    std::size_t& count) noexcept {
    const std::uint64_t value = static_cast<std::uint64_t>(width) * height;
    if (value == 0U || value > static_cast<std::uint64_t>(
            std::numeric_limits<std::size_t>::max())) {
        return false;
    }
    count = static_cast<std::size_t>(value);
    return true;
}

[[nodiscard]] double sinc(const double value) noexcept {
    if (std::abs(value) <= std::numeric_limits<double>::epsilon()) {
        return 1.0;
    }
    const double angle = pi * value;
    return std::sin(angle) / angle;
}

[[nodiscard]] double lanczos(const double value) noexcept {
    if (std::abs(value) >= lanczos_radius) {
        return 0.0;
    }
    return sinc(value) * sinc(value / lanczos_radius);
}

[[nodiscard]] AxisKernel make_axis_kernel(
    const std::uint32_t source_size,
    const std::uint32_t output_size,
    const double scale) {
    AxisKernel result{};
    result.spans.reserve(output_size);
    const double filter_scale = std::min(1.0, scale);
    const double support = lanczos_radius / filter_scale;
    for (std::uint32_t output = 0U; output < output_size; ++output) {
        const double center = (static_cast<double>(output) + 0.5) / scale - 0.5;
        const std::int64_t first = static_cast<std::int64_t>(std::ceil(center - support));
        const std::int64_t last = static_cast<std::int64_t>(std::floor(center + support));
        const std::size_t offset = result.sources.size();
        double weight_sum = 0.0;
        for (std::int64_t source = first; source <= last; ++source) {
            const double weight = lanczos((center - static_cast<double>(source)) * filter_scale);
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
        if (count == 0U || std::abs(weight_sum) <= std::numeric_limits<double>::epsilon()) {
            const std::uint32_t nearest = static_cast<std::uint32_t>(
                std::clamp<std::int64_t>(
                    static_cast<std::int64_t>(std::llround(center)),
                    0, static_cast<std::int64_t>(source_size) - 1));
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
    const WorkingImage& source,
    const std::uint32_t source_y,
    const AxisKernel& horizontal,
    const std::uint32_t output_width) {
    CachedRow result{};
    result.source_y = source_y;
    result.pixels.resize(output_width);
    const auto* const row = source.pixels.data() +
        static_cast<std::size_t>(source_y) * source.stride_pixels;
    for (std::uint32_t output_x = 0U; output_x < output_width; ++output_x) {
        const AxisSpan span = horizontal.spans[output_x];
        negaflow::core::Rgba32F sum{};
        for (std::size_t tap = 0U; tap < span.count; ++tap) {
            const std::size_t index = span.first + tap;
            const auto pixel = row[horizontal.sources[index]];
            const float weight = horizontal.weights[index];
            sum.red += pixel.red * weight;
            sum.green += pixel.green * weight;
            sum.blue += pixel.blue * weight;
        }
        // The develop/export working contract is opaque. Preserve that exact value
        // rather than letting two floating-point filter passes introduce a tiny drift.
        sum.alpha = 1.0F;
        result.pixels[output_x] = sum;
    }
    return result;
}

[[nodiscard]] const CachedRow& cached_horizontal_row(
    std::vector<CachedRow>& cache,
    const WorkingImage& source,
    const std::uint32_t source_y,
    const AxisKernel& horizontal,
    const std::uint32_t output_width) {
    const auto found = std::find_if(
        cache.begin(), cache.end(),
        [&](const CachedRow& row) { return row.source_y == source_y; });
    if (found != cache.end()) {
        return *found;
    }
    cache.push_back(make_horizontal_row(source, source_y, horizontal, output_width));
    return cache.back();
}

}  // namespace

WorkingImageResampleResult resample_working_image_lanczos3(
    const WorkingImage& source,
    const std::uint32_t output_width,
    const std::uint32_t output_height) noexcept {
    WorkingImageResampleResult result{};
    std::size_t source_count = 0U;
    std::size_t source_buffer_count = 0U;
    std::size_t output_count = 0U;
    if (!checked_pixel_count(source.width, source.height, source_count) ||
        !checked_pixel_count(source.stride_pixels, source.height, source_buffer_count) ||
        source.stride_pixels < source.width || source.pixels.size() < source_buffer_count) {
        result.status = WorkingImageResampleStatus::invalid_source;
        return result;
    }
    if (!checked_pixel_count(output_width, output_height, output_count)) {
        result.status = WorkingImageResampleStatus::invalid_dimensions;
        return result;
    }
    if (output_width > source.width || output_height > source.height) {
        result.status = WorkingImageResampleStatus::invalid_dimensions;
        return result;
    }
    if (output_width == source.width && output_height == source.height) {
        result.image = source;
        result.status = WorkingImageResampleStatus::ok;
        return result;
    }
    try {
        const double uniform_scale = source.width >= source.height
            ? static_cast<double>(output_width) / source.width
            : static_cast<double>(output_height) / source.height;
        const AxisKernel horizontal = make_axis_kernel(
            source.width, output_width, uniform_scale);
        const AxisKernel vertical = make_axis_kernel(
            source.height, output_height, uniform_scale);
        result.image.width = output_width;
        result.image.height = output_height;
        result.image.stride_pixels = output_width;
        result.image.pixels.resize(output_count);
        std::vector<CachedRow> cache{};
        std::size_t maximum_vertical_taps = 0U;
        for (const AxisSpan span : vertical.spans) {
            maximum_vertical_taps = std::max(maximum_vertical_taps, span.count);
        }
        cache.reserve(maximum_vertical_taps);
        std::vector<const CachedRow*> rows{};
        rows.reserve(maximum_vertical_taps);
        for (std::uint32_t output_y = 0U; output_y < output_height; ++output_y) {
            const AxisSpan vertical_span = vertical.spans[output_y];
            std::uint32_t minimum_source_y = source.height - 1U;
            for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
                minimum_source_y = std::min(
                    minimum_source_y,
                    vertical.sources[vertical_span.first + tap]);
            }
            cache.erase(
                std::remove_if(
                    cache.begin(), cache.end(),
                    [&](const CachedRow& row) { return row.source_y < minimum_source_y; }),
                cache.end());
            rows.clear();
            for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
                const std::uint32_t source_y = vertical.sources[vertical_span.first + tap];
                rows.push_back(&cached_horizontal_row(
                    cache, source, source_y, horizontal, output_width));
            }
            for (std::uint32_t output_x = 0U; output_x < output_width; ++output_x) {
                negaflow::core::Rgba32F sum{};
                for (std::size_t tap = 0U; tap < vertical_span.count; ++tap) {
                    const float weight = vertical.weights[vertical_span.first + tap];
                    const auto pixel = rows[tap]->pixels[output_x];
                    sum.red += pixel.red * weight;
                    sum.green += pixel.green * weight;
                    sum.blue += pixel.blue * weight;
                }
                sum.alpha = 1.0F;
                result.image.pixels[static_cast<std::size_t>(output_y) * output_width + output_x] =
                    sum;
            }
        }
        result.status = WorkingImageResampleStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.image = {};
        result.status = WorkingImageResampleStatus::allocation_failed;
        return result;
    } catch (...) {
        result.image = {};
        result.status = WorkingImageResampleStatus::size_overflow;
        return result;
    }
}

const char* working_image_resample_status_name(const WorkingImageResampleStatus status) noexcept {
    switch (status) {
        case WorkingImageResampleStatus::ok: return "ok";
        case WorkingImageResampleStatus::invalid_source: return "invalid_source";
        case WorkingImageResampleStatus::invalid_dimensions: return "invalid_dimensions";
        case WorkingImageResampleStatus::size_overflow: return "size_overflow";
        case WorkingImageResampleStatus::allocation_failed: return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
