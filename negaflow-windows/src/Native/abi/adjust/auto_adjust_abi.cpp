#include "negaflow/abi/auto_adjust.h"

#include "negaflow/imaging/auto_adjust.h"

#include <cstdint>
#include <cstring>

// 미리보기 화소에서 자동 톤·화이트밸런스 값을 계산합니다.

nf_status_t NF_CALL nf_auto_adjust_v1(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    nf_auto_adjust_result_v1* const result) {
    if (pixels == nullptr || result == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    negaflow::imaging::AutoAdjustStats stats{};
    if (!negaflow::imaging::compute_auto_adjust_stats(
            pixels,
            width,
            height,
            static_cast<std::size_t>(stride_bytes),
            stats)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    const negaflow::imaging::AutoToneResult tone = negaflow::imaging::auto_tone(stats);
    const negaflow::imaging::AutoWhiteBalanceResult balance =
        negaflow::imaging::auto_white_balance(stats);

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->exposure = tone.exposure;
    result->contrast = tone.contrast;
    result->highlights = tone.highlights;
    result->shadows = tone.shadows;
    result->whites = tone.whites;
    result->blacks = tone.blacks;
    result->density = tone.density;
    result->vibrance = tone.vibrance;
    result->warmth = balance.warmth;
    result->tint = balance.tint;
    return NF_STATUS_OK;
}
