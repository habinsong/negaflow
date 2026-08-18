#include "negaflow/imaging/local_dodge_burn.h"

#include "local_dodge_burn_masks.h"
#include "local_dodge_burn_types.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::local_dodge_burn_detail;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
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


void apply_adjustment(
    WorkingImage& image,
    const LocalDodgeBurnAdjustment& adjustment,
    const std::vector<float>& mask) noexcept {
    const float amount = clamp_unit(adjustment.amount);
    const float stops = adjustment.mode == LocalDodgeBurnMode::dodge
        ? amount
        : -amount;
    const float exposure = std::exp2(stops);
    negaflow::core::for_each_row_block(
        image.height,
        static_cast<std::uint64_t>(image.width) *
            static_cast<std::uint64_t>(image.height),
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
      for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        auto* const row = image.pixels.data() +
            static_cast<std::size_t>(y) * image.stride_pixels;
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float weight = mask[index_of(x, y, image.width)];
            if (weight <= 0.0F) {
                continue;
            }
            const float scale = 1.0F + (exposure - 1.0F) * weight;
            row[x].red *= scale;
            row[x].green *= scale;
            row[x].blue *= scale;
        }
      }
        });
}

[[nodiscard]] bool finite_point(const LocalDodgeBurnPoint point) noexcept {
    return std::isfinite(point.x) && std::isfinite(point.y);
}

}  // namespace

bool valid_local_dodge_burn_parameters(
    const LocalDodgeBurnParameters& parameters) noexcept {
    if (parameters.adjustments.size() >
        local_dodge_burn_maximum_adjustments) {
        return false;
    }
    std::size_t total_points = 0U;
    for (const LocalDodgeBurnAdjustment& adjustment : parameters.adjustments) {
        if (!std::isfinite(adjustment.amount) ||
            static_cast<std::uint8_t>(adjustment.mode) >
                static_cast<std::uint8_t>(LocalDodgeBurnMode::burn) ||
            static_cast<std::uint8_t>(adjustment.mask.kind) >
                static_cast<std::uint8_t>(LocalDodgeBurnMaskKind::polygon) ||
            !finite_point(adjustment.mask.center) ||
            !finite_point(adjustment.mask.start) ||
            !finite_point(adjustment.mask.end) ||
            !std::isfinite(adjustment.mask.radius) ||
            !std::isfinite(adjustment.mask.feather) ||
            adjustment.mask.strokes.size() >
                local_dodge_burn_maximum_strokes_per_mask) {
            return false;
        }
        if (adjustment.mask.points.size() >
            local_dodge_burn_maximum_points - total_points) {
            return false;
        }
        total_points += adjustment.mask.points.size();
        for (const LocalDodgeBurnPoint point : adjustment.mask.points) {
            if (!finite_point(point)) {
                return false;
            }
        }
        for (const LocalDodgeBurnStroke& stroke : adjustment.mask.strokes) {
            if (!std::isfinite(stroke.thickness) ||
                !std::isfinite(stroke.feather) ||
                stroke.points.size() >
                    local_dodge_burn_maximum_points - total_points) {
                return false;
            }
            total_points += stroke.points.size();
            for (const LocalDodgeBurnPoint point : stroke.points) {
                if (!finite_point(point)) {
                    return false;
                }
            }
        }
    }
    return true;
}

LocalDodgeBurnResult apply_local_dodge_burn(
    WorkingImage image,
    const LocalDodgeBurnParameters& parameters) noexcept {
    LocalDodgeBurnResult result{};
    result.image = std::move(image);
    if (!valid_local_dodge_burn_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = LocalDodgeBurnStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.adjustments.empty()) {
        result.status = LocalDodgeBurnStatus::ok;
        return result;
    }

    try {
        for (const LocalDodgeBurnAdjustment& adjustment :
             parameters.adjustments) {
            if (!adjustment.enabled ||
                clamp_unit(adjustment.amount) <=
                    adjustment_identity_threshold) {
                continue;
            }
            MaskResult mask = make_mask(adjustment.mask, result.image);
            result.info.mask_scratch_peak_bytes = std::max(
                result.info.mask_scratch_peak_bytes,
                mask.scratch_peak_bytes);
            if (mask.weights.empty() || !mask_has_weight(mask.weights)) {
                continue;
            }
            apply_adjustment(result.image, adjustment, mask.weights);
            ++result.info.adjustments_applied;
        }
        result.info.applied = result.info.adjustments_applied != 0U;
        result.status = LocalDodgeBurnStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = LocalDodgeBurnStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = LocalDodgeBurnStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* local_dodge_burn_status_name(
    const LocalDodgeBurnStatus status) noexcept {
    switch (status) {
        case LocalDodgeBurnStatus::ok:
            return "ok";
        case LocalDodgeBurnStatus::invalid_parameter:
            return "invalid_parameter";
        case LocalDodgeBurnStatus::kernel_failed:
            return "kernel_failed";
        case LocalDodgeBurnStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}


}  // namespace negaflow::imaging
