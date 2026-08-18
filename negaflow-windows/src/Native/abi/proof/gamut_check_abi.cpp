#include "negaflow/abi/soft_proof.h"

#include "negaflow/color/gamut_check.h"

#include <cstdint>

// 출력 색공간이 색역 경고를 지원하는지 묻습니다.

nf_status_t NF_CALL nf_gamut_check_supported_v1(
    const uint32_t output_color_space,
    uint32_t* const supported) {
    if (supported == nullptr) return NF_STATUS_INVALID_ARGUMENT;
    *supported = 0U;
    if (negaflow::color::output_color_space_name(
            static_cast<negaflow::color::OutputColorSpace>(output_color_space)) == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *supported = negaflow::color::gamut_check_supported(
        static_cast<negaflow::color::OutputColorSpace>(output_color_space)) ? 1U : 0U;
    return NF_STATUS_OK;
}
