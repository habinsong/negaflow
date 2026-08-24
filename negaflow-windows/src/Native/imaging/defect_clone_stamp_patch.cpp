#include "defect_clone_stamp_patch.h"

#include "defect_clone_stamp_mask.h"
#include "defect_clone_stamp_patch_stack.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging::clone_stamp_detail {
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

}  // namespace

[[nodiscard]] PatchBuildStatus make_patch(
    const WorkingImage& base,
    const std::vector<StoredPatch>& preceding,
    const DefectCloneStroke& stroke,
    StoredPatch& patch,
    const negaflow::core::CancelFlag cancel) {
    const auto started = TimingClock::now();
    if (stroke.points.empty()) {
        return PatchBuildStatus::no_change;
    }
    const long long offset_x = std::llround(
        stroke.offset_x * static_cast<double>(base.width));
    const long long offset_y = std::llround(
        stroke.offset_y * static_cast<double>(base.height));
    if (offset_x == 0LL && offset_y == 0LL) {
        return PatchBuildStatus::no_change;
    }

    std::vector<PixelPoint> points{};
    points.reserve(stroke.points.size());
    double minimum_x = std::numeric_limits<double>::max();
    double minimum_y = std::numeric_limits<double>::max();
    double maximum_x = -std::numeric_limits<double>::max();
    double maximum_y = -std::numeric_limits<double>::max();
    for (const DefectClonePoint point : stroke.points) {
        const PixelPoint pixel{
            point.x * static_cast<double>(base.width),
            point.y * static_cast<double>(base.height),
        };
        points.push_back(pixel);
        minimum_x = std::min(minimum_x, pixel.x);
        minimum_y = std::min(minimum_y, pixel.y);
        maximum_x = std::max(maximum_x, pixel.x);
        maximum_y = std::max(maximum_y, pixel.y);
    }

    const double radius = std::max(0.5, stroke.diameter_pixels / 2.0);
    const double padding = radius + antialias_pixels + 1.0;
    const long long left = std::max(
        0LL, static_cast<long long>(std::floor(minimum_x - padding)));
    const long long top = std::max(
        0LL, static_cast<long long>(std::floor(minimum_y - padding)));
    const long long right = std::min(
        static_cast<long long>(base.width),
        static_cast<long long>(std::ceil(maximum_x + padding)));
    const long long bottom = std::min(
        static_cast<long long>(base.height),
        static_cast<long long>(std::ceil(maximum_y + padding)));
    if (left >= right || top >= bottom) {
        return PatchBuildStatus::no_change;
    }
    const auto width = static_cast<std::uint32_t>(right - left);
    const auto height = static_cast<std::uint32_t>(bottom - top);
    if (static_cast<std::size_t>(width) >
        std::numeric_limits<std::size_t>::max() / height) {
        throw std::bad_alloc{};
    }
    std::vector<float> mask(static_cast<std::size_t>(width) * height, 0.0F);
    const auto prepared = TimingClock::now();
    if (!rasterize_stroke(
        points,
        std::max(1.0, stroke.diameter_pixels * stamp_spacing_fraction),
        radius,
        stroke.hardness,
        static_cast<std::uint32_t>(left),
        static_cast<std::uint32_t>(top),
        width,
        height,
        mask,
        cancel)) {
        return PatchBuildStatus::cancelled;
    }
    const auto masked = TimingClock::now();

    std::uint32_t local_left = width;
    std::uint32_t local_top = height;
    std::uint32_t local_right = 0U;
    std::uint32_t local_bottom = 0U;
    bool any = false;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            if (mask[index] <= 0.0F) {
                continue;
            }
            const long long source_x = left + x + offset_x;
            const long long source_y = top + y + offset_y;
            if (source_x < 0LL || source_y < 0LL ||
                source_x >= static_cast<long long>(base.width) ||
                source_y >= static_cast<long long>(base.height)) {
                mask[index] = 0.0F;
                continue;
            }
            any = true;
            local_left = std::min(local_left, x);
            local_top = std::min(local_top, y);
            local_right = std::max(local_right, x);
            local_bottom = std::max(local_bottom, y);
        }
    }
    if (!any) {
        return cancel.requested()
            ? PatchBuildStatus::cancelled
            : PatchBuildStatus::no_change;
    }
    if (cancel.requested()) {
        return PatchBuildStatus::cancelled;
    }
    const auto bounded = TimingClock::now();

    patch.x = static_cast<std::uint32_t>(left) + local_left;
    patch.y = static_cast<std::uint32_t>(top) + local_top;
    patch.width = local_right - local_left + 1U;
    patch.height = local_bottom - local_top + 1U;
    const std::size_t pixel_count =
        static_cast<std::size_t>(patch.width) * patch.height;
    if (pixel_count > defect_clone_maximum_patch_bytes /
                          (4U * sizeof(std::uint16_t))) {
        throw std::bad_alloc{};
    }
    patch.rgba16.resize(pixel_count * 4U);
    for (std::uint32_t y = 0U; y < patch.height; ++y) {
        for (std::uint32_t x = 0U; x < patch.width; ++x) {
            const std::uint32_t destination_x = patch.x + x;
            const std::uint32_t destination_y = patch.y + y;
            const std::size_t mask_index =
                static_cast<std::size_t>(local_top + y) * width +
                local_left + x;
            const float alpha = mask[mask_index];
            const auto destination = full_strength_pixel(
                base, preceding, destination_x, destination_y);
            const auto source = full_strength_pixel(
                base,
                preceding,
                static_cast<std::uint32_t>(
                    static_cast<long long>(destination_x) + offset_x),
                static_cast<std::uint32_t>(
                    static_cast<long long>(destination_y) + offset_y));
            const float inverse = 1.0F - alpha;
            const std::size_t output =
                (static_cast<std::size_t>(y) * patch.width + x) * 4U;
            patch.rgba16[output] = encode_linear16(
                alpha > 0.0F
                    ? source.red * alpha + destination.red * inverse
                    : destination.red);
            patch.rgba16[output + 1U] = encode_linear16(
                alpha > 0.0F
                    ? source.green * alpha + destination.green * inverse
                    : destination.green);
            patch.rgba16[output + 2U] = encode_linear16(
                alpha > 0.0F
                    ? source.blue * alpha + destination.blue * inverse
                    : destination.blue);
            patch.rgba16[output + 3U] = 65'535U;
        }
    }
    const auto filled = TimingClock::now();
    if (timing_enabled()) {
        (void)std::fprintf(
            stderr,
            "[clone patch timing] pixels=%zu prepare=%llu mask=%llu bounds=%llu "
            "fill=%llu total=%llu us\n",
            pixel_count,
            static_cast<unsigned long long>(elapsed_microseconds(started, prepared)),
            static_cast<unsigned long long>(elapsed_microseconds(prepared, masked)),
            static_cast<unsigned long long>(elapsed_microseconds(masked, bounded)),
            static_cast<unsigned long long>(elapsed_microseconds(bounded, filled)),
            static_cast<unsigned long long>(elapsed_microseconds(started, filled)));
    }
    return PatchBuildStatus::ready;
}

}  // namespace negaflow::imaging::clone_stamp_detail
