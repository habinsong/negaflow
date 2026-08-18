#include "negaflow/abi/grain_mend_detect.h"

#include "grain_mend_detect_shared.h"

#include "support/abi_text.h"
#include "request/develop_request_map.h"
#include "result/develop_result_write.h"

#include "negaflow/pipeline/develop_export.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>

using namespace negaflow::abi::detail;

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
