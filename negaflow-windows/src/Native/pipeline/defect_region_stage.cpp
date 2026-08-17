#include "negaflow/pipeline/defect_region_stage.h"

#include <cstdio>
#include <cstdlib>
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

[[nodiscard]] bool region_debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
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
            // 어느 조건이 region 을 건너뛰게 하는지 밖에서 물어볼 수 없었습니다.
            if (region_debug_enabled()) {
                // 커널과 같은 기준으로 셉니다. 0 이면 마스크가 손상을 표시하지 못한 것입니다.
                std::size_t nonzero = 0U;
                std::size_t over_gate = 0U;
                std::uint8_t peak = 0U;
                for (const std::uint8_t value : edit.mask) {
                    if (value != 0U) {
                        ++nonzero;
                    }
                    if (value > 8U) {
                        ++over_gate;
                    }
                    peak = std::max(peak, value);
                }
                std::fprintf(
                    stderr,
                    "[nega-region-mask] nonzero=%llu over_gate=%llu peak=%u\n",
                    static_cast<unsigned long long>(nonzero),
                    static_cast<unsigned long long>(over_gate),
                    static_cast<unsigned>(peak));
                std::fprintf(
                    stderr,
                    "[nega-region] enabled=%d strength=%.6f roi=%llux%llu+%llu+%llu "
                    "mask_bytes=%llu stride=%llu\n",
                    edit.enabled ? 1 : 0,
                    static_cast<double>(edit.repair.strength),
                    static_cast<unsigned long long>(edit.width),
                    static_cast<unsigned long long>(edit.height),
                    static_cast<unsigned long long>(edit.roi_x),
                    static_cast<unsigned long long>(edit.roi_y),
                    static_cast<unsigned long long>(edit.mask.size()),
                    static_cast<unsigned long long>(edit.mask_stride_bytes));
                std::fflush(stderr);
            }
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

            // 수리 커널은 마스크를 화소당 1바이트로 읽습니다(브러시·IR·시험 모두 그렇게
            // 보냅니다). region 편집만 catalog 의 RGBA8 마스크를 그대로 싣고 오므로, 선언된
            // stride 가 정확히 width*4 일 때만 한 채널로 펴서 넘깁니다. 펴지 않으면 커널이 각
            // 행의 앞 width 바이트, 즉 화소 0..width/4 의 R·G·B·A 를 화소 가중치로 잘못 읽어
            // 행의 3/4 를 보지 못하고 아무것도 고치지 않습니다.
            const bool rgba_mask =
                edit.mask_stride_bytes == static_cast<std::size_t>(edit.width) * 4U &&
                edit.mask.size() >=
                    static_cast<std::size_t>(edit.height) * edit.mask_stride_bytes;
            std::vector<std::uint8_t> single_channel;
            if (rgba_mask) {
                single_channel.resize(
                    static_cast<std::size_t>(edit.width) * edit.height);
                for (std::uint32_t y = 0U; y < edit.height; ++y) {
                    const std::size_t source_row =
                        static_cast<std::size_t>(y) * edit.mask_stride_bytes;
                    const std::size_t destination_row =
                        static_cast<std::size_t>(y) * edit.width;
                    for (std::uint32_t x = 0U; x < edit.width; ++x) {
                        single_channel[destination_row + x] =
                            edit.mask[source_row + (static_cast<std::size_t>(x) * 4U)];
                    }
                }
            }
            auto repaired = negaflow::imaging::repair_defect_components(
                std::move(roi),
                rgba_mask ? std::span<const std::uint8_t>{single_channel} : edit.mask,
                rgba_mask ? static_cast<std::size_t>(edit.width) : edit.mask_stride_bytes,
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
