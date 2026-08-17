#include "negaflow_abi.h"

#include "negaflow/imaging/manual_negative_developer.h"
#include "negaflow/imaging/working_tone_adjuster.h"

#include <cstdint>

// 톤·네거티브 수동 입력의 허용 범위를 돌려줍니다.

nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->maximum_exposure_stops = negaflow::imaging::maximum_exposure_stops;
    output->maximum_tone_control = negaflow::imaging::maximum_tone_control;
    output->minimum_film_emulation_intensity = 0.0;
    output->maximum_film_emulation_intensity = 1.0;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}

nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* const output) {
    if (output == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (output->struct_size < static_cast<std::uint32_t>(sizeof(*output))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::uint32_t declared_size = output->struct_size;
    output->minimum_manual_dmin = negaflow::imaging::minimum_manual_dmin;
    output->maximum_manual_dmin = negaflow::imaging::maximum_manual_dmin;
    output->struct_size = declared_size;
    return NF_STATUS_OK;
}
