#include "negaflow/pipeline/defect_region_stage.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::pipeline {
namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::WorkingImage;

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool valid_image_layout(const WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
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

[[nodiscard]] bool valid_mask_layout(const DefectRegionEdit& edit) noexcept {
    if (edit.width <= 2U || edit.height <= 2U ||
        edit.mask_stride_bytes < edit.width) {
        return false;
    }
    const std::size_t height_minus_one = edit.height - 1U;
    if (height_minus_one != 0U &&
        edit.mask_stride_bytes >
            (std::numeric_limits<std::size_t>::max() - edit.width) /
                height_minus_one) {
        return false;
    }
    return edit.mask.size() >=
           height_minus_one * edit.mask_stride_bytes + edit.width;
}

[[nodiscard]] bool valid_edit(
    const DefectRegionEdit& edit,
    const WorkingImage& image) noexcept {
    return edit.roi_x <= image.width && edit.width <= image.width - edit.roi_x &&
           edit.roi_y <= image.height && edit.height <= image.height - edit.roi_y &&
           valid_mask_layout(edit) &&
           std::isfinite(edit.repair.strength) &&
           edit.repair.strength >= 0.0 && edit.repair.strength <= 1.0 &&
           (!edit.repair.has_preferred_angle ||
            (std::isfinite(edit.repair.preferred_angle_degrees) &&
             edit.repair.preferred_angle_degrees >= 0.0 &&
             edit.repair.preferred_angle_degrees <= 180.0));
}

[[nodiscard]] DefectRegionStageStatus map_status(
    const negaflow::imaging::DefectComponentRepairStatus status) noexcept {
    switch (status) {
        case negaflow::imaging::DefectComponentRepairStatus::ok:
            return DefectRegionStageStatus::ok;
        case negaflow::imaging::DefectComponentRepairStatus::invalid_argument:
            return DefectRegionStageStatus::invalid_argument;
        case negaflow::imaging::DefectComponentRepairStatus::kernel_failed:
            return DefectRegionStageStatus::kernel_failed;
        case negaflow::imaging::DefectComponentRepairStatus::allocation_failed:
            return DefectRegionStageStatus::allocation_failed;
    }
    return DefectRegionStageStatus::invalid_argument;
}

}  // namespace

DefectRegionStageResult apply_defect_region_edits(
    WorkingImage image,
    const DefectRegionParameters& parameters) noexcept {
    DefectRegionStageResult result{};
    result.image = std::move(image);
    if (!valid_image_layout(result.image) ||
        parameters.edits.size() > defect_region_maximum_edits) {
        discard_pixels(result.image);
        return result;
    }
    std::size_t total_mask_bytes = 0U;
    for (const DefectRegionEdit& edit : parameters.edits) {
        if (!valid_edit(edit, result.image) ||
            edit.mask.size() > defect_region_maximum_mask_bytes - total_mask_bytes) {
            discard_pixels(result.image);
            return result;
        }
        total_mask_bytes += edit.mask.size();
    }

    try {
        for (const DefectRegionEdit& edit : parameters.edits) {
            if (!edit.enabled || edit.repair.strength <= 1.0e-3) {
                continue;
            }
            const std::uint32_t top =
                result.image.height - edit.roi_y - edit.height;
            WorkingImage roi{};
            roi.width = edit.width;
            roi.height = edit.height;
            roi.stride_pixels = edit.width;
            roi.pixels.resize(
                static_cast<std::size_t>(edit.width) * edit.height);
            for (std::uint32_t y = 0U; y < edit.height; ++y) {
                const auto source = result.image.pixels.begin() +
                    static_cast<std::ptrdiff_t>(
                        static_cast<std::size_t>(top + y) *
                            result.image.stride_pixels +
                        edit.roi_x);
                std::copy_n(
                    source,
                    edit.width,
                    roi.pixels.begin() +
                        static_cast<std::ptrdiff_t>(
                            static_cast<std::size_t>(y) * edit.width));
            }

            auto repaired = negaflow::imaging::repair_defect_components(
                std::move(roi),
                edit.mask,
                edit.mask_stride_bytes,
                edit.repair);
            if (repaired.status !=
                negaflow::imaging::DefectComponentRepairStatus::ok) {
                result.status = map_status(repaired.status);
                discard_pixels(result.image);
                return result;
            }
            for (std::uint32_t y = 0U; y < edit.height; ++y) {
                auto destination = result.image.pixels.begin() +
                    static_cast<std::ptrdiff_t>(
                        static_cast<std::size_t>(top + y) *
                            result.image.stride_pixels +
                        edit.roi_x);
                std::copy_n(
                    repaired.image.pixels.begin() +
                        static_cast<std::ptrdiff_t>(
                            static_cast<std::size_t>(y) * edit.width),
                    edit.width,
                    destination);
            }
            if (repaired.info.applied) {
                result.info.applied = true;
                ++result.info.applied_edit_count;
                result.info.repaired_pixels += repaired.info.repaired_pixels;
            }
        }
        result.status = DefectRegionStageStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectRegionStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectRegionStageStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_region_stage_status_name(
    const DefectRegionStageStatus status) noexcept {
    switch (status) {
        case DefectRegionStageStatus::ok:
            return "ok";
        case DefectRegionStageStatus::invalid_argument:
            return "invalid_argument";
        case DefectRegionStageStatus::kernel_failed:
            return "kernel_failed";
        case DefectRegionStageStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::pipeline
