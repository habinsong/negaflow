#pragma once

#include "negaflow/abi/grain_mend_detect.h"

#include <cstdint>

namespace negaflow::pipeline {
struct GrainMendDetectionOutcome;
}

namespace negaflow::abi::detail {

// v4·v5·v6 의 공유 몸통입니다. 두 벌로 두면 한쪽만 고쳐질 자리라 하나만 둡니다.
// `components` 가 null 이 아니면 채택된 결함을 분류까지 복사하고, 언제나 개수는 채웁니다.
// `automatic_false_positive_risk`·`automatic_candidate_pixel_fraction` 은 v6 만 받아 갑니다.
[[nodiscard]] nf_status_t detect_grain_mend_shared(
    const nf_develop_export_request_v27* request,
    const nf_grain_mend_detect_parameters_v3* parameters,
    uint8_t* mask,
    uint64_t mask_capacity_bytes,
    nf_grain_mend_component_v1* components,
    uint64_t component_capacity,
    nf_grain_mend_preview_point_v1* preview_points,
    uint64_t preview_point_capacity,
    uint64_t* preview_point_count,
    uint64_t* component_count,
    uint32_t* automatic_false_positive_risk,
    double* automatic_candidate_pixel_fraction,
    nf_develop_run_state_v1* run_state,
    nf_grain_mend_detection_v2* detection,
    nf_develop_export_result_v3* result,
    negaflow::pipeline::GrainMendDetectionOutcome* retained_detection = nullptr);

}  // namespace negaflow::abi::detail
