#include "negaflow/imaging/grain_mend.h"

#include "grain_mend_components.h"
#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_speck_detector.h"
#include "grain_mend_tiled.h"

#include <algorithm>
#include <array>
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
using grain_mend_detail::merge_micro_speck_mask;
using grain_mend_detail::AutomaticDetection;
using grain_mend_detail::build_tiled_automatic_mask;
using grain_mend_detail::make_detection_image_region;
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

[[nodiscard]] std::size_t checked_pixel_count(
    const std::uint32_t width,
    const std::uint32_t height) {
    if (width == 0U || height == 0U ||
        static_cast<std::size_t>(width) >
            std::numeric_limits<std::size_t>::max() /
                static_cast<std::size_t>(height)) {
        throw std::bad_alloc{};
    }
    return static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
}

[[nodiscard]] negaflow::core::Rgba32F median_3x3(
    const WorkingImage& image,
    const std::uint32_t x,
    const std::uint32_t y) noexcept {
    std::array<float, 9U> red{};
    std::array<float, 9U> green{};
    std::array<float, 9U> blue{};
    std::size_t sample = 0U;
    for (int dy = -1; dy <= 1; ++dy) {
        const std::uint32_t sample_y = dy < 0
            ? (y == 0U ? 0U : y - 1U)
            : (dy > 0 && y < image.height - 1U ? y + 1U : y);
        for (int dx = -1; dx <= 1; ++dx) {
            const std::uint32_t sample_x = dx < 0
                ? (x == 0U ? 0U : x - 1U)
                : (dx > 0 && x < image.width - 1U ? x + 1U : x);
            const auto pixel = image.pixels[
                static_cast<std::size_t>(sample_y) * image.stride_pixels + sample_x];
            red[sample] = pixel.red;
            green[sample] = pixel.green;
            blue[sample] = pixel.blue;
            ++sample;
        }
    }
    constexpr std::size_t middle = 4U;
    std::nth_element(red.begin(), red.begin() + middle, red.end());
    std::nth_element(green.begin(), green.begin() + middle, green.end());
    std::nth_element(blue.begin(), blue.begin() + middle, blue.end());
    return {red[middle], green[middle], blue[middle], 1.0F};
}

void repair_full_resolution(
    WorkingImage& image,
    const DetectionImage& detection,
    const std::vector<std::uint8_t>& mask,
    const float strength,
    std::size_t& repaired_pixels) {
    struct PendingRepair final {
        std::size_t index{0U};
        negaflow::core::Rgba32F median{};
        float blend{0.0F};
    };
    std::vector<PendingRepair> previous_row{};
    std::vector<PendingRepair> current_row{};
    previous_row.reserve(image.width);
    current_row.reserve(image.width);
    const auto apply_row = [&](const std::vector<PendingRepair>& repairs) noexcept {
        for (const PendingRepair& repair : repairs) {
            const auto original = image.pixels[repair.index];
            auto& destination = image.pixels[repair.index];
            const float blend = strength * repair.blend;
            const float local_inverse = 1.0F - blend;
            destination.red = original.red * local_inverse + repair.median.red * blend;
            destination.green =
                original.green * local_inverse + repair.median.green * blend;
            destination.blue =
                original.blue * local_inverse + repair.median.blue * blend;
            destination.alpha = original.alpha;
        }
    };
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        current_row.clear();
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            const float mask_weight = sample_transformed_mask(
                mask,
                detection.width,
                detection.height,
                image.width,
                image.height,
                x,
                y);
            if (mask_weight <= 0.0F) {
                continue;
            }
            const std::size_t index =
                static_cast<std::size_t>(y) * image.stride_pixels + x;
            current_row.push_back({index, median_3x3(image, x, y), mask_weight});
            ++repaired_pixels;
        }
        apply_row(previous_row);
        previous_row.swap(current_row);
    }
    apply_row(previous_row);
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
            AutomaticDetection request{};
            request.width = result.image.width;
            request.height = result.image.height;
            request.dust_sensitivity = parameters.dust_sensitivity;
            request.scratch_sensitivity = parameters.scratch_sensitivity;
            request.protect_detail = parameters.protect_detail;
            const std::vector<std::uint8_t> mask =
                build_tiled_automatic_mask(
                    result.image,
                    request,
                    result.info.candidate_pixels,
                    nullptr,
                    nullptr,
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
                repair_full_resolution(
                    result.image,
                    geometry,
                    mask,
                    static_cast<float>(parameters.strength),
                    result.info.repaired_pixels);
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
        std::vector<std::uint8_t> accepted_mask = mask;
        if (parameters.detect_micro_specks) {
            std::size_t added_micro_specks = 0U;
            if (!merge_micro_speck_mask(
                    detection,
                    parameters.dust_sensitivity,
                    accepted_mask,
                    added_micro_specks,
                    cancel)) {
                result.status = GrainMendStatus::cancelled;
                discard_pixels(result.image);
                return result;
            }
            result.info.candidate_pixels += added_micro_specks;
        }
        if (result.info.candidate_pixels != 0U) {
            repair_full_resolution(
                result.image,
                detection,
                accepted_mask,
                static_cast<float>(parameters.strength),
                result.info.repaired_pixels);
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

GrainMendDetection detect_grain_mend(
    const WorkingImage& image,
    const GrainMendParameters& parameters,
    const GrainMendRoi roi,
    const negaflow::core::CancelFlag cancel) noexcept {
    GrainMendDetection detection{};
    // 세기는 검출에 쓰이지 않지만 나머지 감도는 같은 검사를 통과해야 합니다. 세기만 0 이라고
    // 거절하면 "아직 아무것도 안 걸린 프레임"에서 검출을 못 하게 됩니다.
    GrainMendParameters probe = parameters;
    probe.strength = maximum_grain_mend_strength;
    if (!valid_grain_mend_parameters(probe) || image.width == 0U ||
        image.height == 0U || image.pixels.empty()) {
        return detection;
    }

    if (!std::isfinite(roi.x) || !std::isfinite(roi.y) ||
        !std::isfinite(roi.width) || !std::isfinite(roi.height) ||
        roi.width <= 0.0 || roi.height <= 0.0) {
        return detection;
    }

    try {
        // 부분 ROI 는 그 범위만 분석합니다. 전체를 재고 나중에 가리면 주변 통계가 달라져
        // 사용자가 고른 범위 안에서 macOS 와 다른 것을 찾습니다.
        std::uint32_t left = 0U;
        std::uint32_t top = 0U;
        std::uint32_t right = image.width;
        std::uint32_t bottom = image.height;
        if (!roi.covers_everything()) {
            const auto width = static_cast<double>(image.width);
            const auto height = static_cast<double>(image.height);
            left = static_cast<std::uint32_t>(
                std::clamp(std::floor(roi.x * width), 0.0, width - 1.0));
            top = static_cast<std::uint32_t>(
                std::clamp(std::floor(roi.y * height), 0.0, height - 1.0));
            right = static_cast<std::uint32_t>(std::clamp(
                std::ceil((roi.x + roi.width) * width),
                static_cast<double>(left) + 1.0,
                width));
            bottom = static_cast<std::uint32_t>(std::clamp(
                std::ceil((roi.y + roi.height) * height),
                static_cast<double>(top) + 1.0,
                height));
        }
        // macOS `detectComponents` 는 **다운스케일 없이** 봅니다. 자동을 1800px 로 줄여
        // 보면 3~8px 짜리 진짜 먼지가 게이트 아래로 사라지고, 수천 px 짜리 직선 구조물만
        // 살아남아 스크래치로 잡힙니다.
        AutomaticDetection request{};
        request.origin_x = left;
        request.origin_y = top;
        request.width = right - left;
        request.height = bottom - top;
        request.dust_sensitivity = parameters.dust_sensitivity;
        request.scratch_sensitivity = parameters.scratch_sensitivity;
        request.protect_detail = parameters.protect_detail;
        // macOS `constrainedRegion`: 자동(전체 프레임)은 언제나 거짓입니다. ROI 가 반올림으로
        // 1px 어긋나도 전역 자동 계약이 유지되어야 오검출이 폭증하지 않습니다.
        request.constrained_region =
            !parameters.reject_structure_lines && !roi.covers_everything();
        request.detect_micro_specks = parameters.detect_micro_specks;
        detection.width = request.width;
        detection.height = request.height;
        detection.roi_x = left;
        detection.roi_y = top;
        detection.roi_width = request.width;
        detection.roi_height = request.height;
        detection.mask = build_tiled_automatic_mask(
            image,
            request,
            detection.accepted_pixels,
            &detection.components,
            &detection.timings,
            cancel);
        if (cancel.requested()) {
            detection.status = GrainMendStatus::cancelled;
            return detection;
        }
        detection.status = GrainMendStatus::ok;
        return detection;
    } catch (...) {
        detection.mask.clear();
        detection.accepted_pixels = 0U;
        detection.status = GrainMendStatus::allocation_failed;
        return detection;
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
