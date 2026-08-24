#include "negaflow/abi/grain_mend_detect.h"

#include "grain_mend_detect_shared.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/abi/develop_enums.h"
#include "negaflow/imaging/grain_mend_review.h"
#include "negaflow/pipeline/develop_export.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>
#include <span>
#include <utility>

using namespace negaflow::abi::detail;

struct nf_grain_mend_review_handle_v1 final {
    explicit nf_grain_mend_review_handle_v1(
        negaflow::imaging::GrainMendReview&& value)
        : review(std::move(value)) {}

    negaflow::imaging::GrainMendReview review;
};

struct nf_grain_mend_accepted_region_handle_v1 final {
    explicit nf_grain_mend_accepted_region_handle_v1(
        negaflow::imaging::GrainMendAcceptedRegion&& value)
        : accepted(std::move(value)) {}

    negaflow::imaging::GrainMendAcceptedRegion accepted;
};

namespace {

[[nodiscard]] std::size_t preview_stride(
    const std::size_t pixel_count,
    const std::size_t component_count) noexcept {
    constexpr std::size_t total_preview_budget = 24'000U;
    constexpr std::size_t maximum_preview_per_component = 800U;
    const std::size_t per_component = std::max<std::size_t>(
        1U,
        std::min(
            maximum_preview_per_component,
            total_preview_budget / std::max<std::size_t>(1U, component_count)));
    return std::max<std::size_t>(
        1U,
        (pixel_count + per_component - 1U) / per_component);
}

void fail_review_result(
    nf_develop_export_result_v3& result,
    const char* const failure_name) noexcept {
    result.succeeded = 0U;
    result.failed_stage = NF_DEVELOP_STAGE_GRAIN_MEND;
    copy_failure_name(failure_name, result.failure_name);
}

[[nodiscard]] std::uint32_t accepted_status(
    const negaflow::imaging::GrainMendAcceptedRegionStatus status) noexcept {
    using Status = negaflow::imaging::GrainMendAcceptedRegionStatus;
    switch (status) {
        case Status::ok:
            return NF_GRAIN_MEND_ACCEPTED_OK;
        case Status::empty:
            return NF_GRAIN_MEND_ACCEPTED_EMPTY;
        case Status::invalid_geometry:
            return NF_GRAIN_MEND_ACCEPTED_INVALID_GEOMETRY;
        case Status::allocation_failed:
            return NF_GRAIN_MEND_ACCEPTED_ALLOCATION_FAILED;
    }
    return NF_GRAIN_MEND_ACCEPTED_INVALID_GEOMETRY;
}

}  // namespace

// GrainMend 자동 검출 C ABI v4-v6 입니다. 셋 다 공유 몸통 하나를 부릅니다.

nf_status_t NF_CALL nf_develop_detect_grain_mend_v4(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v3* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    return detect_grain_mend_shared(
        request,
        parameters,
        mask,
        mask_capacity_bytes,
        nullptr,
        0U,
        nullptr,
        0U,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        run_state,
        detection,
        result);
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v5(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v3* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* const components,
    const uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v3* const detection,
    nf_develop_export_result_v3* const result) {
    // 중첩 구조는 안쪽 v2 가 전체 크기를 말합니다 — nf_grain_mend_detect_parameters_v3 와
    // 같은 규약이라 호출부가 두 벌의 규칙을 외우지 않아도 됩니다.
    if (detection == nullptr ||
        detection->v2.struct_size <
            static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    return detect_grain_mend_shared(
        request,
        parameters,
        mask,
        mask_capacity_bytes,
        components,
        component_capacity,
        preview_points,
        preview_point_capacity,
        &detection->preview_point_count,
        &detection->component_count,
        nullptr,
        nullptr,
        run_state,
        &detection->v2,
        result);
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v6(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v3* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* const components,
    const uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v4* const detection,
    nf_develop_export_result_v3* const result) {
    // v5 와 같은 규약입니다 — 가장 안쪽 v2 의 struct_size 가 전체 크기를 말합니다.
    if (detection == nullptr ||
        detection->v3.v2.struct_size <
            static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    return detect_grain_mend_shared(
        request,
        parameters,
        mask,
        mask_capacity_bytes,
        components,
        component_capacity,
        preview_points,
        preview_point_capacity,
        &detection->v3.preview_point_count,
        &detection->v3.component_count,
        &detection->automatic_false_positive_risk,
        &detection->automatic_candidate_pixel_fraction,
        run_state,
        &detection->v3.v2,
        result);
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v7(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v3* const parameters,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v4* const detection,
    nf_develop_export_result_v3* const result,
    nf_grain_mend_review_handle_v1** const review) {
    if (review == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *review = nullptr;
    if (detection == nullptr ||
        detection->v3.v2.struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::pipeline::GrainMendDetectionOutcome retained{};
    const nf_status_t status = detect_grain_mend_shared(
        request,
        parameters,
        nullptr,
        0U,
        nullptr,
        0U,
        nullptr,
        0U,
        &detection->v3.preview_point_count,
        &detection->v3.component_count,
        &detection->automatic_false_positive_risk,
        &detection->automatic_candidate_pixel_fraction,
        run_state,
        &detection->v3.v2,
        result,
        &retained);
    if (status != NF_STATUS_OK || result == nullptr || result->succeeded == 0U ||
        retained.components.empty()) {
        return status;
    }

    try {
        negaflow::imaging::GrainMendReview exact{
            retained.width,
            retained.height,
            retained.source_width,
            retained.source_height,
            retained.roi_x,
            retained.roi_y,
            retained.roi_width,
            retained.roi_height,
            std::move(retained.components)};
        if (!exact.valid()) {
            fail_review_result(*result, "grain_mend_review_invalid");
            return NF_STATUS_OK;
        }
        auto* const owned = new (std::nothrow)
            nf_grain_mend_review_handle_v1{std::move(exact)};
        if (owned == nullptr) {
            fail_review_result(*result, "allocation_failed");
            return NF_STATUS_OK;
        }
        *review = owned;
        return NF_STATUS_OK;
    } catch (const std::bad_alloc&) {
        fail_review_result(*result, "allocation_failed");
        return NF_STATUS_OK;
    } catch (...) {
        fail_review_result(*result, "grain_mend_review_invalid");
        return NF_STATUS_OK;
    }
}

nf_status_t NF_CALL nf_grain_mend_review_copy_components_v1(
    const nf_grain_mend_review_handle_v1* const review,
    nf_grain_mend_component_v1* const components,
    const uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity) {
    if (review == nullptr ||
        (components == nullptr) != (component_capacity == 0U) ||
        (preview_points == nullptr) != (preview_point_capacity == 0U) ||
        (components == nullptr && preview_points != nullptr)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const auto& source = review->review.components();
    const std::size_t point_count = review->review.preview_point_count();
    if (component_capacity < source.size() ||
        (preview_points != nullptr && preview_point_capacity < point_count)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (components == nullptr) return NF_STATUS_OK;

    std::size_t written = 0U;
    for (std::size_t index = 0U; index < source.size(); ++index) {
        const auto& component = source[index];
        const std::size_t stride = preview_stride(component.pixels.size(), source.size());
        const std::size_t taken =
            (component.pixels.size() + stride - 1U) / stride;
        nf_grain_mend_component_v1& target = components[index];
        target.struct_size = static_cast<std::uint32_t>(sizeof(target));
        target.classification = static_cast<std::uint32_t>(component.classification);
        target.confidence = component.confidence;
        target.area = component.pixels.size();
        target.minimum_x = component.minimum_x;
        target.minimum_y = component.minimum_y;
        target.maximum_x = component.maximum_x;
        target.maximum_y = component.maximum_y;
        target.preview_point_offset = written;
        target.preview_point_count = taken;
        if (preview_points != nullptr) {
            std::size_t point = 0U;
            for (std::size_t pixel = 0U;
                 pixel < component.pixels.size();
                 pixel += stride) {
                preview_points[written + point] = nf_grain_mend_preview_point_v1{
                    static_cast<std::uint32_t>(
                        component.pixels[pixel] % review->review.width()),
                    static_cast<std::uint32_t>(
                        component.pixels[pixel] / review->review.width())};
                ++point;
            }
        }
        written += taken;
    }
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_grain_mend_review_hit_test_v1(
    const nf_grain_mend_review_handle_v1* const review,
    const int32_t x,
    const int32_t y,
    const uint32_t radius,
    nf_grain_mend_review_hit_v1* const hit) {
    if (review == nullptr || hit == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    if (hit->struct_size < static_cast<std::uint32_t>(sizeof(*hit))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    const std::uint32_t declared_size = hit->struct_size;
    std::memset(hit, 0, sizeof(*hit));
    hit->struct_size = declared_size;
    if (const auto found = review->review.nearest_component(x, y, radius)) {
        hit->found = 1U;
        hit->component_index = *found;
    }
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_grain_mend_review_build_accepted_v1(
    const nf_grain_mend_review_handle_v1* const review,
    const uint8_t* const excluded,
    const uint64_t excluded_count,
    nf_grain_mend_accepted_region_v1* const accepted,
    nf_grain_mend_accepted_region_handle_v1** const accepted_handle) {
    if (review == nullptr || accepted == nullptr || accepted_handle == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *accepted_handle = nullptr;
    if (accepted->struct_size < static_cast<std::uint32_t>(sizeof(*accepted))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }
    if (excluded_count != review->review.components().size() ||
        (excluded_count != 0U && excluded == nullptr)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    const std::uint32_t declared_size = accepted->struct_size;
    std::memset(accepted, 0, sizeof(*accepted));
    accepted->struct_size = declared_size;
    auto region = review->review.build_accepted(
        std::span<const std::uint8_t>(
            excluded, static_cast<std::size_t>(excluded_count)));
    accepted->status = accepted_status(region.status);
    accepted->roi_x = region.roi_x;
    accepted->roi_y = region.roi_y;
    accepted->width = region.width;
    accepted->height = region.height;
    accepted->mask_byte_count = region.rgba.size();
    accepted->included_component_count = region.included_component_count;
    if (region.status != negaflow::imaging::GrainMendAcceptedRegionStatus::ok) {
        return NF_STATUS_OK;
    }
    auto* const owned = new (std::nothrow)
        nf_grain_mend_accepted_region_handle_v1{std::move(region)};
    if (owned == nullptr) {
        accepted->status = NF_GRAIN_MEND_ACCEPTED_ALLOCATION_FAILED;
        accepted->mask_byte_count = 0U;
        accepted->included_component_count = 0U;
        return NF_STATUS_OK;
    }
    *accepted_handle = owned;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_grain_mend_accepted_region_copy_mask_v1(
    const nf_grain_mend_accepted_region_handle_v1* const accepted,
    uint8_t* const rgba,
    const uint64_t rgba_capacity_bytes) {
    if (accepted == nullptr ||
        (rgba == nullptr) != (rgba_capacity_bytes == 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (rgba == nullptr) return NF_STATUS_OK;
    if (rgba_capacity_bytes < accepted->accepted.rgba.size()) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    std::memcpy(
        rgba,
        accepted->accepted.rgba.data(),
        accepted->accepted.rgba.size());
    return NF_STATUS_OK;
}

void NF_CALL nf_grain_mend_accepted_region_destroy_v1(
    nf_grain_mend_accepted_region_handle_v1* const accepted) {
    delete accepted;
}

void NF_CALL nf_grain_mend_review_destroy_v1(
    nf_grain_mend_review_handle_v1* const review) {
    delete review;
}
