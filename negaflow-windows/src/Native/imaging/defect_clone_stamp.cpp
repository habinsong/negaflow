#include "negaflow/imaging/defect_clone_stamp.h"

#include "defect_clone_stamp_patch.h"
#include "defect_clone_stamp_patch_stack.h"
#include "defect_clone_stamp_types.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::clone_stamp_detail;

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

[[nodiscard]] bool valid_layout(const WorkingImage& image) noexcept {
    if (image.width == 0U || image.height == 0U ||
        image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t rows = image.height - 1U;
    return rows == 0U ||
        image.stride_pixels <=
            (std::numeric_limits<std::size_t>::max() - image.width) / rows;
}

[[nodiscard]] bool finite_point(const DefectClonePoint point) noexcept {
    return std::isfinite(point.x) && std::isfinite(point.y);
}

[[nodiscard]] bool valid_parameters(
    const DefectCloneParameters& parameters) noexcept {
    if (!std::isfinite(parameters.strength) || parameters.strength < 0.0 ||
        parameters.strength > 1.0 ||
        parameters.strokes.size() > defect_clone_maximum_strokes) {
        return false;
    }
    std::size_t point_count = 0U;
    for (const DefectCloneStroke& stroke : parameters.strokes) {
        if (!std::isfinite(stroke.offset_x) ||
            !std::isfinite(stroke.offset_y) ||
            !std::isfinite(stroke.diameter_pixels) ||
            stroke.diameter_pixels <= 0.0 ||
            !std::isfinite(stroke.hardness) || stroke.hardness < 0.0 ||
            stroke.hardness > 1.0 ||
            stroke.points.size() > defect_clone_maximum_points - point_count) {
            return false;
        }
        point_count += stroke.points.size();
        if (!std::all_of(
                stroke.points.begin(), stroke.points.end(), finite_point)) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool valid_scaled_geometry(
    const WorkingImage& image,
    const DefectCloneParameters& parameters) noexcept {
    constexpr double safe_integer =
        static_cast<double>(std::numeric_limits<long long>::max()) / 8.0;
    for (const DefectCloneStroke& stroke : parameters.strokes) {
        const double offset_x =
            stroke.offset_x * static_cast<double>(image.width);
        const double offset_y =
            stroke.offset_y * static_cast<double>(image.height);
        if (!std::isfinite(offset_x) || !std::isfinite(offset_y) ||
            std::abs(offset_x) > safe_integer ||
            std::abs(offset_y) > safe_integer ||
            stroke.diameter_pixels > safe_integer) {
            return false;
        }
        for (const DefectClonePoint point : stroke.points) {
            const double x = point.x * static_cast<double>(image.width);
            const double y = point.y * static_cast<double>(image.height);
            if (!std::isfinite(x) || !std::isfinite(y) ||
                std::abs(x) > safe_integer || std::abs(y) > safe_integer) {
                return false;
            }
        }
    }
    return true;
}

}  // namespace

DefectCloneResult apply_defect_clone_stamps(
    WorkingImage image,
    const DefectCloneParameters& parameters) noexcept {
    DefectCloneResult result{};
    result.image = std::move(image);
    if (!valid_layout(result.image) || !valid_parameters(parameters) ||
        !valid_scaled_geometry(result.image, parameters)) {
        discard_pixels(result.image);
        return result;
    }
    result.info.kernel_status =
        negaflow::core::validate_finite_pixels(const_view(result.image));
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = DefectCloneStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }
    if (parameters.strength <= 1.0e-3 || parameters.strokes.empty()) {
        result.status = DefectCloneStatus::ok;
        return result;
    }

    try {
        const WorkingImage& item_base = result.image;
        std::vector<StoredPatch> full_strength_patches{};
        full_strength_patches.reserve(parameters.strokes.size());
        std::size_t stored_patch_bytes = 0U;
        for (const DefectCloneStroke& stroke : parameters.strokes) {
            StoredPatch patch{};
            if (!make_patch(item_base, full_strength_patches, stroke, patch)) {
                continue;
            }
            const std::size_t patch_bytes =
                patch.rgba16.size() * sizeof(std::uint16_t);
            if (patch_bytes > defect_clone_maximum_patch_bytes -
                                  stored_patch_bytes) {
                throw std::bad_alloc{};
            }
            stored_patch_bytes += patch_bytes;
            composite_patch(
                result.image,
                patch,
                static_cast<float>(parameters.strength));
            result.info.applied = true;
            ++result.info.applied_strokes;
            result.info.patched_pixels +=
                static_cast<std::size_t>(patch.width) * patch.height;
            result.info.peak_patch_bytes = stored_patch_bytes;
            full_strength_patches.push_back(std::move(patch));
        }
        result.status = DefectCloneStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = DefectCloneStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    } catch (...) {
        result.status = DefectCloneStatus::allocation_failed;
        discard_pixels(result.image);
        return result;
    }
}

const char* defect_clone_status_name(const DefectCloneStatus status) noexcept {
    switch (status) {
        case DefectCloneStatus::ok:
            return "ok";
        case DefectCloneStatus::invalid_argument:
            return "invalid_argument";
        case DefectCloneStatus::kernel_failed:
            return "kernel_failed";
        case DefectCloneStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
