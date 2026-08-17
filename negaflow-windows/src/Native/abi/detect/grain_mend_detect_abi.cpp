#include "negaflow_abi.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace negaflow::abi::detail;

// GrainMend 자동 검출 C ABI 입니다. 마스크·분류 복사는 공유 몸통 하나입니다.

nf_status_t NF_CALL nf_develop_detect_grain_mend_v1(
    const nf_develop_export_request_v27* const request,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v1* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control);
    const auto finished = std::chrono::steady_clock::now();
    // 버퍼가 모자라 실패한 경우에도 필요한 크기는 알려 줍니다 — 그래야 한 번 더 부르면 됩니다.
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v2(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v1* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (parameters == nullptr ||
        parameters->struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->reserved != 0U || detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    detection->source_width = 0U;
    detection->source_height = 0U;
    detection->roi_x = 0U;
    detection->roi_y = 0U;
    detection->roi_width = 0U;
    detection->roi_height = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    const negaflow::imaging::GrainMendRoi roi{
        parameters->roi_x,
        parameters->roi_y,
        parameters->roi_width,
        parameters->roi_height,
    };
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control,
            roi);
    const auto finished = std::chrono::steady_clock::now();
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    detection->source_width = detected.source_width;
    detection->source_height = detected.source_height;
    detection->roi_x = detected.roi_x;
    detection->roi_y = detected.roi_y;
    detection->roi_width = detected.roi_width;
    detection->roi_height = detected.roi_height;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_develop_detect_grain_mend_v3(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v2* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (parameters == nullptr ||
        parameters->v1.struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->v1.reserved != 0U || parameters->reserved != 0U ||
        !std::isfinite(parameters->dust_sensitivity) ||
        !std::isfinite(parameters->scratch_sensitivity) ||
        !std::isfinite(parameters->protect_detail) ||
        parameters->dust_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->dust_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->scratch_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->scratch_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->protect_detail < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->protect_detail > negaflow::imaging::maximum_grain_mend_sensitivity ||
        detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    detection->source_width = 0U;
    detection->source_height = 0U;
    detection->roi_x = 0U;
    detection->roi_y = 0U;
    detection->roi_width = 0U;
    detection->roi_height = 0U;
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    pipeline_request.grain_mend.dust_sensitivity = parameters->dust_sensitivity;
    pipeline_request.grain_mend.scratch_sensitivity = parameters->scratch_sensitivity;
    pipeline_request.grain_mend.protect_detail = parameters->protect_detail;
    pipeline_request.grain_mend.reject_structure_lines =
        parameters->reject_structure_lines != 0U;
    pipeline_request.grain_mend.detect_micro_specks = false;
    const negaflow::imaging::GrainMendRoi roi{
        parameters->v1.roi_x,
        parameters->v1.roi_y,
        parameters->v1.roi_width,
        parameters->v1.roi_height,
    };
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control,
            roi);
    const auto finished = std::chrono::steady_clock::now();
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    detection->source_width = detected.source_width;
    detection->source_height = detected.source_height;
    detection->roi_x = detected.roi_x;
    detection->roi_y = detected.roi_y;
    detection->roi_width = detected.roi_width;
    detection->roi_height = detected.roi_height;
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

// v4 와 v5 의 몸통입니다. 두 벌로 두면 한쪽만 고쳐질 자리라 하나만 둡니다.
// `components` 가 null 이 아니면 채택된 결함을 분류까지 복사하고, 언제나 개수는 채웁니다.
static nf_status_t detect_grain_mend_shared(
    const nf_develop_export_request_v27* const request,
    const nf_grain_mend_detect_parameters_v3* const parameters,
    uint8_t* const mask,
    const uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* const components,
    const uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* const preview_points,
    const uint64_t preview_point_capacity,
    uint64_t* const preview_point_count,
    uint64_t* const component_count,
    nf_develop_run_state_v1* const run_state,
    nf_grain_mend_detection_v2* const detection,
    nf_develop_export_result_v3* const result) {
    nf_status_t status = NF_STATUS_OK;
    if (!prepare_result_v27(request, result, status)) {
        return status;
    }
    if (parameters == nullptr ||
        parameters->v2.v1.struct_size < static_cast<std::uint32_t>(sizeof(*parameters)) ||
        parameters->v2.v1.reserved != 0U || parameters->v2.reserved != 0U ||
        parameters->reserved != 0U ||
        !std::isfinite(parameters->v2.dust_sensitivity) ||
        !std::isfinite(parameters->v2.scratch_sensitivity) ||
        !std::isfinite(parameters->v2.protect_detail) ||
        parameters->v2.dust_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->v2.dust_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->v2.scratch_sensitivity < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->v2.scratch_sensitivity > negaflow::imaging::maximum_grain_mend_sensitivity ||
        parameters->v2.protect_detail < negaflow::imaging::minimum_grain_mend_sensitivity ||
        parameters->v2.protect_detail > negaflow::imaging::maximum_grain_mend_sensitivity ||
        detection == nullptr ||
        detection->struct_size < static_cast<std::uint32_t>(sizeof(*detection))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    detection->width = 0U;
    detection->height = 0U;
    detection->accepted_pixels = 0U;
    detection->mask_byte_count = 0U;
    detection->source_width = 0U;
    detection->source_height = 0U;
    detection->roi_x = 0U;
    detection->roi_y = 0U;
    detection->roi_width = 0U;
    detection->roi_height = 0U;
    if (component_count != nullptr) {
        *component_count = 0U;
    }
    if (preview_point_count != nullptr) {
        *preview_point_count = 0U;
    }
    negaflow::pipeline::DevelopRunControl control{};
    if (!prepare_run_state(run_state, control, status)) {
        return status;
    }
    negaflow::pipeline::DevelopExportRequest pipeline_request{};
    nf_develop_export_result_v2 mapping_result{};
    mapping_result.struct_size = static_cast<std::uint32_t>(sizeof(mapping_result));
    copy_failure_name("ok", mapping_result.failure_name);
    if (!map_request_v27(*request, false, pipeline_request, mapping_result)) {
        write_request_rejection_v3(mapping_result, *result);
        return NF_STATUS_OK;
    }
    pipeline_request.grain_mend.dust_sensitivity = parameters->v2.dust_sensitivity;
    pipeline_request.grain_mend.scratch_sensitivity = parameters->v2.scratch_sensitivity;
    pipeline_request.grain_mend.protect_detail = parameters->v2.protect_detail;
    pipeline_request.grain_mend.reject_structure_lines =
        parameters->v2.reject_structure_lines != 0U;
    pipeline_request.grain_mend.detect_micro_specks =
        parameters->detect_micro_specks != 0U;
    const negaflow::imaging::GrainMendRoi roi{
        parameters->v2.v1.roi_x,
        parameters->v2.v1.roi_y,
        parameters->v2.v1.roi_width,
        parameters->v2.v1.roi_height,
    };
    const auto started = std::chrono::steady_clock::now();
    const negaflow::pipeline::GrainMendDetectionOutcome detected =
        negaflow::pipeline::develop_detect_grain_mend(
            pipeline_request,
            mask,
            static_cast<std::size_t>(mask_capacity_bytes),
            control,
            roi);
    const auto finished = std::chrono::steady_clock::now();
    detection->width = detected.width;
    detection->height = detected.height;
    detection->accepted_pixels = detected.accepted_pixels;
    detection->mask_byte_count = detected.mask_byte_count;
    detection->source_width = detected.source_width;
    detection->source_height = detected.source_height;
    detection->roi_x = detected.roi_x;
    detection->roi_y = detected.roi_y;
    detection->roi_width = detected.roi_width;
    detection->roi_height = detected.roi_height;
    // 컴포넌트는 마스크와 같은 두 번 부르기 규약입니다: 버퍼가 null 이면 개수만
    // 알려 주고, 모자라면 거절합니다 — 잘라 담으면 화면이 일부만 보고 판단합니다.
    //
    // 미리보기 점은 macOS `previewComponents` 와 같은 규칙으로 솎습니다: 전체 예산
    // 24,000 점을 컴포넌트 수로 나누되 하나당 800 을 넘지 않게 하고, 그 수에 맞는
    // 간격으로 건너뛰며 고릅니다. 전부 실으면 화면이 과밀해지고 비용도 큽니다.
    if (component_count != nullptr) {
        constexpr std::size_t total_preview_budget = 24000U;
        constexpr std::size_t maximum_preview_per_component = 800U;
        *component_count = detected.components.size();
        const std::size_t per_component = std::max<std::size_t>(
            1U,
            std::min(
                maximum_preview_per_component,
                total_preview_budget /
                    std::max<std::size_t>(1U, detected.components.size())));
        std::size_t total_points = 0U;
        for (const auto& source : detected.components) {
            const std::size_t stride = std::max<std::size_t>(
                1U,
                (source.pixels.size() + per_component - 1U) / per_component);
            total_points += (source.pixels.size() + stride - 1U) / stride;
        }
        if (preview_point_count != nullptr) {
            *preview_point_count = total_points;
        }
        if (components != nullptr) {
            if (component_capacity < detected.components.size() ||
                (preview_points != nullptr &&
                 preview_point_capacity < total_points)) {
                result->succeeded = 0U;
                copy_failure_name(
                    "component_buffer_too_small",
                    result->failure_name);
                return NF_STATUS_OK;
            }
            std::size_t written = 0U;
            for (std::size_t index = 0U; index < detected.components.size(); ++index) {
                const auto& source = detected.components[index];
                nf_grain_mend_component_v1& target = components[index];
                target.struct_size = static_cast<std::uint32_t>(sizeof(target));
                target.classification =
                    static_cast<std::uint32_t>(source.classification);
                target.confidence = source.confidence;
                target.area = source.pixels.size();
                target.minimum_x = source.minimum_x;
                target.minimum_y = source.minimum_y;
                target.maximum_x = source.maximum_x;
                target.maximum_y = source.maximum_y;
                target.preview_point_offset = written;
                const std::size_t stride = std::max<std::size_t>(
                    1U,
                    (source.pixels.size() + per_component - 1U) / per_component);
                std::size_t taken = 0U;
                for (std::size_t pixel = 0U;
                     pixel < source.pixels.size();
                     pixel += stride) {
                    if (preview_points != nullptr) {
                        nf_grain_mend_preview_point_v1& point =
                            preview_points[written + taken];
                        point.x = static_cast<std::uint32_t>(
                            source.pixels[pixel] % detected.width);
                        point.y = static_cast<std::uint32_t>(
                            source.pixels[pixel] / detected.width);
                    }
                    ++taken;
                }
                target.preview_point_count = taken;
                written += taken;
            }
        }
    }
    write_outcome_v3(
        detected.outcome, elapsed_microseconds(started, finished), *result);
    return NF_STATUS_OK;
}

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
        run_state,
        &detection->v2,
        result);
}
