#include "defect_heal_brush_repair.h"

#include "defect_heal_brush_patch_search.h"
#include "defect_heal_brush_patch_stack.h"
#include "defect_heal_brush_stroke.h"

#include "defect_component_repair_detail.h"
#include "grain_mend_morphology.h"
#include "grain_mend_shape.h"

#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/defect_component_repair.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <new>
#include <optional>
#include <utility>

namespace negaflow::imaging::heal_brush_detail {
namespace {

using TimingClock = std::chrono::steady_clock;

[[nodiscard]] bool timing_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_TIMING") == 0 && length > 0U;
}

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const TimingClock::time_point started,
    const TimingClock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

// 형태 측정은 grain_mend_shape 하나만 씁니다. 두께와 각도만 쓰지만 같은 셈이어야
// 브러시가 보는 획 방향과 검출 게이트가 보는 방향이 갈리지 않습니다.
[[nodiscard]] grain_mend_detail::PcaMetrics pca_metrics(
    const std::vector<int>& component,
    const int width) noexcept {
    return grain_mend_detail::pca_metrics(component, width);
}

[[nodiscard]] bool heal_component(
    const std::vector<int>& component,
    const defect_component_repair_detail::ComponentBounds& bounds,
    const std::vector<Rgba32F>& source,
    const std::vector<std::uint8_t>& damaged,
    const int width,
    const int height,
    const std::optional<double> preferred_angle,
    std::vector<Rgba32F>& healed) {
    const grain_mend_detail::PcaMetrics pca = pca_metrics(component, width);
    const double angle_degrees = preferred_angle.value_or(pca.angle_degrees);
    const double axis = angle_degrees * tuning::pi / 180.0;
    const double thickness = std::max(4.0, pca.thickness);
    const int base = static_cast<int>(std::llround(thickness + 6.0));
    std::vector<Displacement> candidates{};
    const double perpendicular = axis + tuning::pi * 0.5;
    for (const double multiple : {1.4, 2.0, 2.8}) {
        add_displacement(candidates, perpendicular, base * multiple);
    }
    for (const double multiple : {1.6, 2.4}) {
        add_displacement(candidates, axis, base * multiple);
    }
    for (const double multiple : {1.7, 2.5}) {
        add_displacement(
            candidates, perpendicular + tuning::pi * 0.25, base * multiple);
        add_displacement(
            candidates, perpendicular - tuning::pi * 0.25, base * multiple);
    }
    const std::vector<int> ring = context_ring(
        damaged, width, height, bounds);
    std::optional<Displacement> best{};
    double best_ssd = std::numeric_limits<double>::max();
    for (const Displacement candidate : candidates) {
        bool valid = true;
        for (const int pixel : component) {
            const int y = pixel / width;
            const int x = pixel - y * width;
            const int sx = x + candidate.dx;
            const int sy = y + candidate.dy;
            if (sx < 0 || sy < 0 || sx >= width || sy >= height ||
                damaged[static_cast<std::size_t>(sy) * width + sx] != 0U) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            continue;
        }
        const double ssd = context_ssd(
            ring, candidate, source, damaged, width, height);
        if (!best.has_value() || ssd < best_ssd) {
            best = candidate;
            best_ssd = ssd;
        }
    }
    if (!best.has_value()) {
        return false;
    }

    std::vector<Rgba32F> filled = source;
    for (const int pixel : component) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const auto value = cross_fill(
            source, damaged, width, height, x, y, axis);
        if (value.has_value()) {
            filled[static_cast<std::size_t>(pixel)].red = value->red;
            filled[static_cast<std::size_t>(pixel)].green = value->green;
            filled[static_cast<std::size_t>(pixel)].blue = value->blue;
        }
    }
    const std::uint32_t radius = static_cast<std::uint32_t>(std::max(
        4,
        std::min(16, static_cast<int>(std::llround(thickness * 0.5)))));
    std::array<std::vector<float>, 3U> low{};
    // 채널끼리는 읽기·쓰기 공유가 없고 각 box_mean 내부의 합산 순서는 그대로입니다.
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(low.size()),
        static_cast<std::uint64_t>(filled.size()) * low.size() *
            (sizeof(Rgba32F) + sizeof(float)),
        [&](const std::uint32_t first_channel, const std::uint32_t channel_count) noexcept {
            for (std::uint32_t channel = first_channel;
                 channel < first_channel + channel_count;
                 ++channel) {
                std::vector<float> values(filled.size());
                for (std::size_t pixel = 0U; pixel < filled.size(); ++pixel) {
                    values[pixel] = channel == 0U
                        ? filled[pixel].red
                        : channel == 1U ? filled[pixel].green : filled[pixel].blue;
                }
                low[channel] = grain_mend_detail::box_mean(
                    values,
                    static_cast<std::uint32_t>(width),
                    static_cast<std::uint32_t>(height),
                    radius);
            }
        });
    for (const int pixel : component) {
        const int y = pixel / width;
        const int x = pixel - y * width;
        const int sample =
            (y + best->dy) * width + (x + best->dx);
        const std::size_t destination = static_cast<std::size_t>(pixel);
        const std::size_t source_pixel = static_cast<std::size_t>(sample);
        healed[destination].red = std::clamp(
            source[source_pixel].red + low[0][destination] - low[0][source_pixel],
            0.0F,
            1.0F);
        healed[destination].green = std::clamp(
            source[source_pixel].green + low[1][destination] - low[1][source_pixel],
            0.0F,
            1.0F);
        healed[destination].blue = std::clamp(
            source[source_pixel].blue + low[2][destination] - low[2][source_pixel],
            0.0F,
            1.0F);
    }
    return true;
}

[[nodiscard]] StoredPatch fallback_patch(
    const std::vector<Rgba32F>& linear,
    const std::vector<float>& mask,
    const Rect bounds,
    const std::optional<double> angle) {
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    WorkingImage roi{};
    roi.width = static_cast<std::uint32_t>(width);
    roi.height = static_cast<std::uint32_t>(height);
    roi.stride_pixels = static_cast<std::uint32_t>(width);
    roi.pixels = linear;
    std::vector<std::uint8_t> weights(mask.size());
    for (std::size_t pixel = 0U; pixel < mask.size(); ++pixel) {
        weights[pixel] = static_cast<std::uint8_t>(std::clamp(
            std::floor(static_cast<double>(mask[pixel]) * 255.0 + 0.5),
            0.0,
            255.0));
    }
    DefectComponentRepairParameters parameters{};
    parameters.has_preferred_angle = angle.has_value();
    parameters.preferred_angle_degrees = angle.value_or(0.0);
    auto repaired = repair_defect_components(
        std::move(roi), weights, static_cast<std::size_t>(width), parameters);
    if (repaired.status != DefectComponentRepairStatus::ok) {
        throw std::bad_alloc{};
    }
    return {
        bounds.left,
        bounds.top,
        width,
        height,
        std::move(repaired.image.pixels),
    };
}

}  // namespace

StoredPatch make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const BrushChunk& chunk,
    bool& used_fallback,
    std::size_t& component_count,
    std::size_t& healed_pixels) {
    const auto started = TimingClock::now();
    const int image_width = static_cast<int>(base.width);
    const int image_height = static_cast<int>(base.height);
    const Rect bounds = repair_bounds(
        chunk, image_width, image_height);
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    if (width <= 4 || height <= 4) {
        return {};
    }
    const std::size_t count = static_cast<std::size_t>(width) * height;
    if (count > defect_heal_brush_maximum_patch_bytes / sizeof(Rgba32F)) {
        throw std::bad_alloc{};
    }
    std::vector<Rgba32F> linear(count);
    std::vector<Rgba32F> encoded(count);
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(height),
        static_cast<std::uint64_t>(count) * sizeof(Rgba32F) * 3U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (int x = 0; x < width; ++x) {
                    const std::size_t pixel = static_cast<std::size_t>(y) * width + x;
                    linear[pixel] = full_strength_pixel(
                        base, preceding, bounds.left + x, bounds.top + y);
                    encoded[pixel] = {
                        negaflow::color::linear_to_srgb_encoded(linear[pixel].red),
                        negaflow::color::linear_to_srgb_encoded(linear[pixel].green),
                        negaflow::color::linear_to_srgb_encoded(linear[pixel].blue),
                        linear[pixel].alpha,
                    };
                }
            }
        });
    const auto extracted = TimingClock::now();
    const std::vector<float> mask = rasterize_mask(
        chunk, bounds, image_width, image_height);
    std::vector<std::uint8_t> damaged(count, 0U);
    for (std::size_t pixel = 0U; pixel < count; ++pixel) {
        if (mask[pixel] * 255.0F > 8.0F) {
            damaged[pixel] = 1U;
            ++healed_pixels;
        }
    }
    const auto angle = stroke_angle(chunk, image_width, image_height);
    const auto masked = TimingClock::now();
    std::vector<Rgba32F> healed = encoded;
    bool all_healed = true;
    defect_component_repair_detail::for_each_component(
        damaged,
        width,
        height,
        [&](const std::vector<int>& component,
            const defect_component_repair_detail::ComponentBounds& component_bounds) {
            if (!all_healed) {
                return;
            }
            ++component_count;
            all_healed = heal_component(
                component,
                component_bounds,
                encoded,
                damaged,
                width,
                height,
                angle,
                healed);
        });
    if (!all_healed) {
        used_fallback = true;
        return fallback_patch(linear, mask, bounds, angle);
    }
    const auto healed_at = TimingClock::now();

    const std::vector<float> feathered = gaussian_radius_one(mask, width, height);
    StoredPatch patch{};
    patch.left = bounds.left;
    patch.top = bounds.top;
    patch.width = width;
    patch.height = height;
    patch.pixels.resize(count);
    negaflow::core::for_each_row_block(
        static_cast<std::uint32_t>(height),
        static_cast<std::uint64_t>(count) * sizeof(Rgba32F) * 3U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            const std::size_t begin = static_cast<std::size_t>(first_row) * width;
            const std::size_t end =
                static_cast<std::size_t>(first_row + row_count) * width;
            for (std::size_t pixel = begin; pixel < end; ++pixel) {
                const float blend = std::clamp(feathered[pixel], 0.0F, 1.0F);
                const float keep = 1.0F - blend;
                const Rgba32F repaired_linear{
                    negaflow::color::srgb_encoded_to_linear(healed[pixel].red),
                    negaflow::color::srgb_encoded_to_linear(healed[pixel].green),
                    negaflow::color::srgb_encoded_to_linear(healed[pixel].blue),
                    linear[pixel].alpha,
                };
                patch.pixels[pixel] = {
                    linear[pixel].red * keep + repaired_linear.red * blend,
                    linear[pixel].green * keep + repaired_linear.green * blend,
                    linear[pixel].blue * keep + repaired_linear.blue * blend,
                    linear[pixel].alpha,
                };
            }
        });
    const auto finished = TimingClock::now();
    if (timing_enabled()) {
        (void)std::fprintf(
            stderr,
            "[brush patch timing] pixels=%zu extract=%llu mask=%llu heal=%llu "
            "feather=%llu total=%llu us\n",
            count,
            static_cast<unsigned long long>(elapsed_microseconds(started, extracted)),
            static_cast<unsigned long long>(elapsed_microseconds(extracted, masked)),
            static_cast<unsigned long long>(elapsed_microseconds(masked, healed_at)),
            static_cast<unsigned long long>(elapsed_microseconds(healed_at, finished)),
            static_cast<unsigned long long>(elapsed_microseconds(started, finished)));
    }
    return patch;
}

}  // namespace negaflow::imaging::heal_brush_detail
