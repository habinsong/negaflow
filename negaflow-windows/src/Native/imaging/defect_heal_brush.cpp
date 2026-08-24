#include "negaflow/imaging/defect_heal_brush.h"

#include "defect_heal_brush_patch_stack.h"
#include "defect_heal_brush_repair.h"
#include "defect_heal_brush_stroke.h"
#include "defect_heal_brush_types.h"

#include "negaflow/core/pixel.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::heal_brush_detail;

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

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] negaflow::core::ConstImageView const_view(
    const WorkingImage& image) noexcept {
    return {
        image.pixels.data(),
        image.pixels.size(),
        image.width,
        image.height,
        image.stride_pixels,
    };
}

[[nodiscard]] bool valid_layout(const WorkingImage& image) noexcept {
    if (image.width <= 4U || image.height <= 4U ||
        image.stride_pixels < image.width ||
        image.width > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max()) ||
        image.height > static_cast<std::uint32_t>(
            std::numeric_limits<int>::max())) {
        return false;
    }
    const std::size_t height_minus_one = image.height - 1U;
    if (height_minus_one != 0U &&
        image.stride_pixels >
            (std::numeric_limits<std::size_t>::max() - image.width) /
                height_minus_one) {
        return false;
    }
    return image.pixels.size() >=
        height_minus_one * image.stride_pixels + image.width;
}

[[nodiscard]] bool valid_parameters(
    const DefectHealBrushParameters& parameters) noexcept {
    if (!std::isfinite(parameters.strength) || parameters.strength < 0.0 ||
        parameters.strength > 1.0 ||
        parameters.strokes.size() > tuning::maximum_strokes) {
        return false;
    }
    std::size_t point_count = 0U;
    for (const DefectBrushStroke& stroke : parameters.strokes) {
        if (!std::isfinite(stroke.thickness) || stroke.thickness < 0.0 ||
            stroke.thickness > 1.0 ||
            stroke.points.size() > tuning::maximum_points - point_count) {
            return false;
        }
        point_count += stroke.points.size();
        for (const DefectBrushPoint point : stroke.points) {
            if (!std::isfinite(point.x) || !std::isfinite(point.y) ||
                point.x < 0.0 || point.x > 1.0 ||
                point.y < 0.0 || point.y > 1.0) {
                return false;
            }
        }
    }
    return true;
}

}  // namespace

DefectHealBrushResult apply_defect_heal_brush(
    WorkingImage image,
    const DefectHealBrushParameters& parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    const auto started = TimingClock::now();
    DefectHealBrushResult result{};
    result.image = std::move(image);
    if (!valid_layout(result.image) || !valid_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    const auto kernel_status = negaflow::core::validate_finite_pixels(
        const_view(result.image));
    if (kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DefectHealBrushStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= 1.0e-3 || parameters.strokes.empty()) {
        result.status = DefectHealBrushStatus::ok;
        return result;
    }
    const auto validated = TimingClock::now();
    try {
        std::vector<BrushChunk> chunks{};
        for (const DefectBrushStroke& stroke : parameters.strokes) {
            if (cancel.requested()) {
                result.status = DefectHealBrushStatus::cancelled;
                discard_pixels(result.image);
                return result;
            }
            auto stroke_chunks = make_chunks(
                stroke,
                static_cast<int>(result.image.width),
                static_cast<int>(result.image.height));
            for (BrushChunk& chunk : stroke_chunks) {
                chunks.push_back(std::move(chunk));
            }
        }
        const auto chunked = TimingClock::now();
        std::vector<StoredPatch> patches{};
        patches.reserve(chunks.size());
        std::size_t patch_bytes = 0U;
        for (const BrushChunk& chunk : chunks) {
            if (cancel.requested()) {
                result.status = DefectHealBrushStatus::cancelled;
                discard_pixels(result.image);
                return result;
            }
            bool fallback = false;
            std::size_t components = 0U;
            std::size_t pixels = 0U;
            StoredPatch patch = make_patch(
                result.image,
                patches,
                chunk,
                fallback,
                components,
                pixels);
            if (patch.pixels.empty()) {
                continue;
            }
            const std::size_t bytes = patch.pixels.size() * sizeof(Rgba32F);
            if (bytes > defect_heal_brush_maximum_patch_bytes - patch_bytes) {
                throw std::bad_alloc{};
            }
            patch_bytes += bytes;
            result.info.peak_patch_bytes = std::max(
                result.info.peak_patch_bytes,
                bytes);
            ++result.info.applied_chunk_count;
            result.info.healed_component_count += components;
            result.info.healed_pixels += pixels;
            result.info.fallback_chunk_count += fallback ? 1U : 0U;
            patches.push_back(std::move(patch));
        }
        const auto patched = TimingClock::now();
        if (cancel.requested()) {
            result.status = DefectHealBrushStatus::cancelled;
            discard_pixels(result.image);
            return result;
        }
        const std::size_t covered_pixels = composite_patches(
            result.image,
            patches,
            static_cast<float>(parameters.strength));
        const auto composited = TimingClock::now();
        if (timing_enabled()) {
            (void)std::fprintf(
                stderr,
                "[brush timing] validation=%llu chunks=%llu patches=%llu "
                "composite=%llu total=%llu us chunks_count=%zu covered_pixels=%zu\n",
                static_cast<unsigned long long>(elapsed_microseconds(started, validated)),
                static_cast<unsigned long long>(elapsed_microseconds(validated, chunked)),
                static_cast<unsigned long long>(elapsed_microseconds(chunked, patched)),
                static_cast<unsigned long long>(elapsed_microseconds(patched, composited)),
                static_cast<unsigned long long>(elapsed_microseconds(started, composited)),
                chunks.size(),
                covered_pixels);
        }
        result.info.applied = !patches.empty();
        result.status = DefectHealBrushStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectHealBrushStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectHealBrushStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_heal_brush_status_name(
    const DefectHealBrushStatus status) noexcept {
    switch (status) {
        case DefectHealBrushStatus::ok:
            return "ok";
        case DefectHealBrushStatus::invalid_argument:
            return "invalid_argument";
        case DefectHealBrushStatus::kernel_failed:
            return "kernel_failed";
        case DefectHealBrushStatus::allocation_failed:
            return "allocation_failed";
        case DefectHealBrushStatus::cancelled:
            return "cancelled";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
