#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/defect_component_repair.h"

#include "grain_mend_components.h"
#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_tiled.h"

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

using grain_mend_detail::CandidateMaps;
using grain_mend_detail::DetectionImage;
using grain_mend_detail::build_automatic_mask;
using grain_mend_detail::find_candidates;
using grain_mend_detail::build_tiled_automatic_mask;
using grain_mend_detail::make_detection_image;
using grain_mend_detail::sample_transformed_mask;

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

[[nodiscard]] DefectComponentRepairStatus repair_full_resolution(
    WorkingImage& image,
    const DetectionImage& detection,
    const std::vector<std::uint8_t>& mask,
    const float strength,
    std::size_t& repaired_pixels) {
    std::vector<std::uint8_t> full_mask(
        static_cast<std::size_t>(image.width) * image.height,
        0U);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float mask_weight = sample_transformed_mask(
                mask,
                detection.width,
                detection.height,
                image.width,
                image.height,
                x,
                y);
            full_mask[static_cast<std::size_t>(y) * image.width + x] =
                static_cast<std::uint8_t>(std::lround(
                    std::clamp(mask_weight, 0.0F, 1.0F) * 255.0F));
        }
    }
    const std::size_t mask_stride_bytes = image.width;
    const auto repaired = repair_defect_components(
        std::move(image),
        full_mask,
        mask_stride_bytes,
        {.has_preferred_angle = false, .preferred_angle_degrees = 0.0,
         .strength = static_cast<double>(strength)});
    const DefectComponentRepairStatus status = repaired.status;
    repaired_pixels = repaired.info.repaired_pixels;
    image = std::move(repaired.image);
    return status;
}

}  // namespace

bool valid_grain_mend_parameters(
    const GrainMendParameters& parameters) noexcept {
    return std::isfinite(parameters.strength) &&
           parameters.strength >= minimum_grain_mend_strength &&
           parameters.strength <= maximum_grain_mend_strength &&
           std::isfinite(parameters.dust_sensitivity) &&
           parameters.dust_sensitivity >= minimum_grain_mend_sensitivity &&
           parameters.dust_sensitivity <= maximum_grain_mend_sensitivity &&
           std::isfinite(parameters.scratch_sensitivity) &&
           parameters.scratch_sensitivity >= minimum_grain_mend_sensitivity &&
           parameters.scratch_sensitivity <= maximum_grain_mend_sensitivity &&
           std::isfinite(parameters.protect_detail) &&
           parameters.protect_detail >= minimum_grain_mend_sensitivity &&
           parameters.protect_detail <= maximum_grain_mend_sensitivity;
}

GrainMendResult apply_grain_mend(
    WorkingImage image,
    const GrainMendParameters& parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    GrainMendResult result{};
    result.image = std::move(image);
    if (!valid_grain_mend_parameters(parameters)) {
        discard_pixels(result.image);
        return result;
    }

    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = GrainMendStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= grain_mend_identity_threshold ||
        result.image.width <= 8U || result.image.height <= 8U) {
        result.status = GrainMendStatus::ok;
        return result;
    }

    try {
        if (parameters.reject_structure_lines) {
            result.info.detection_width = result.image.width;
            result.info.detection_height = result.image.height;
            const std::vector<std::uint8_t> mask =
                build_tiled_automatic_mask(
                    result.image,
                    parameters.dust_sensitivity,
                    parameters.scratch_sensitivity,
                    parameters.protect_detail,
                    result.info.candidate_pixels,
                    cancel);
            if (cancel.requested()) {
                result.status = GrainMendStatus::cancelled;
                discard_pixels(result.image);
                return result;
            }
            if (result.info.candidate_pixels != 0U) {
                DetectionImage geometry{};
                geometry.width = result.image.width;
                geometry.height = result.image.height;
                const DefectComponentRepairStatus repair_status = repair_full_resolution(
                    result.image,
                    geometry,
                    mask,
                    static_cast<float>(parameters.strength),
                    result.info.repaired_pixels);
                if (repair_status != DefectComponentRepairStatus::ok) {
                    result.status = repair_status == DefectComponentRepairStatus::kernel_failed
                        ? GrainMendStatus::kernel_failed
                        : GrainMendStatus::allocation_failed;
                    discard_pixels(result.image);
                    return result;
                }
            }
            result.info.applied = result.info.repaired_pixels != 0U;
            result.status = GrainMendStatus::ok;
            return result;
        }
        const DetectionImage detection = make_detection_image(result.image);
        result.info.detection_width = detection.width;
        result.info.detection_height = detection.height;
        const CandidateMaps candidates = find_candidates(
            detection,
            parameters.dust_sensitivity,
            parameters.scratch_sensitivity,
            parameters.protect_detail,
            false,
            cancel);
        if (cancel.requested()) {
            result.status = GrainMendStatus::cancelled;
            discard_pixels(result.image);
            return result;
        }
        const std::vector<std::uint8_t> mask = build_automatic_mask(
            detection,
            candidates,
            parameters.reject_structure_lines,
            result.info.candidate_pixels);
        if (result.info.candidate_pixels != 0U) {
            const DefectComponentRepairStatus repair_status = repair_full_resolution(
                result.image,
                detection,
                mask,
                static_cast<float>(parameters.strength),
                result.info.repaired_pixels);
            if (repair_status != DefectComponentRepairStatus::ok) {
                result.status = repair_status == DefectComponentRepairStatus::kernel_failed
                    ? GrainMendStatus::kernel_failed
                    : GrainMendStatus::allocation_failed;
                discard_pixels(result.image);
                return result;
            }
        }
        result.info.applied = result.info.repaired_pixels != 0U;
        result.status = GrainMendStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = GrainMendStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = GrainMendStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* grain_mend_status_name(const GrainMendStatus status) noexcept {
    switch (status) {
        case GrainMendStatus::ok:
            return "ok";
        case GrainMendStatus::invalid_parameter:
            return "invalid_parameter";
        case GrainMendStatus::kernel_failed:
            return "kernel_failed";
        case GrainMendStatus::cancelled:
            return "cancelled";
        case GrainMendStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
