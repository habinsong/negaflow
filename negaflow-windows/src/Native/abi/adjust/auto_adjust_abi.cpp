#include "negaflow/abi/auto_adjust.h"

#include "negaflow/core/pointwise.h"
#include "negaflow/imaging/auto_adjust.h"

#include <cstdint>
#include <cstring>

// 미리보기 화소에서 자동 톤·화이트밸런스 값을 계산합니다.

namespace {

[[nodiscard]] double headroom_for(const std::uint32_t black_and_white_negative) noexcept {
    return negaflow::core::exposure_headroom_stops(black_and_white_negative != 0U);
}

void write_result(
    const negaflow::imaging::AutoToneResult& tone,
    const negaflow::imaging::AutoWhiteBalanceResult& balance,
    nf_auto_adjust_result_v1& result) noexcept {
    const std::uint32_t declared_size = result.struct_size;
    std::memset(&result, 0, sizeof(result));
    result.struct_size = declared_size;
    result.exposure = tone.exposure;
    result.contrast = tone.contrast;
    result.highlights = tone.highlights;
    result.shadows = tone.shadows;
    result.whites = tone.whites;
    result.blacks = tone.blacks;
    result.density = tone.density;
    result.vibrance = tone.vibrance;
    result.warmth = balance.warmth;
    result.tint = balance.tint;
}

[[nodiscard]] nf_status_t compute(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    const double headroom_stops,
    nf_auto_adjust_result_v1* const result) noexcept {
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

    write_result(
        negaflow::imaging::auto_tone(stats, headroom_stops),
        negaflow::imaging::auto_white_balance(stats),
        *result);
    return NF_STATUS_OK;
}

}  // namespace

nf_status_t NF_CALL nf_auto_adjust_v1(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    nf_auto_adjust_result_v1* const result) {
    return compute(pixels, width, height, stride_bytes, headroom_for(0U), result);
}

nf_status_t NF_CALL nf_auto_adjust_v2(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    const uint32_t black_and_white_negative,
    nf_auto_adjust_result_v1* const result) {
    return compute(
        pixels, width, height, stride_bytes, headroom_for(black_and_white_negative), result);
}

nf_status_t NF_CALL nf_auto_tone_refine_v1(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    const uint32_t black_and_white_negative,
    const nf_auto_adjust_result_v1* const first,
    nf_auto_adjust_result_v1* const refined) {
    if (pixels == nullptr || first == nullptr || refined == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (first->struct_size < static_cast<std::uint32_t>(sizeof(*first)) ||
        refined->struct_size < static_cast<std::uint32_t>(sizeof(*refined))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    negaflow::imaging::AutoAdjustStats measured{};
    if (!negaflow::imaging::compute_auto_adjust_stats(
            pixels,
            width,
            height,
            static_cast<std::size_t>(stride_bytes),
            measured)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    negaflow::imaging::AutoToneResult tone{};
    tone.exposure = first->exposure;
    tone.contrast = first->contrast;
    tone.highlights = first->highlights;
    tone.shadows = first->shadows;
    tone.whites = first->whites;
    tone.blacks = first->blacks;
    tone.density = first->density;
    tone.vibrance = first->vibrance;
    const negaflow::imaging::AutoWhiteBalanceResult balance{first->warmth, first->tint};
    write_result(
        negaflow::imaging::refine_auto_tone(tone, measured, headroom_for(black_and_white_negative)),
        balance,
        *refined);
    return NF_STATUS_OK;
}
