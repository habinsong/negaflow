#include "negaflow/abi/soft_proof.h"

#include "negaflow/color/soft_proof.h"

#include <cstdint>
#include <cstring>
#include <span>

// ICC 바이트에서 소프트 프루프 용지 흰점·먹점을 읽습니다.

nf_status_t NF_CALL nf_read_soft_proof_media_v1(
    const uint8_t* const icc_bytes,
    const uint32_t icc_byte_count,
    nf_soft_proof_media_v1* const result) {
    if (result == nullptr || (icc_bytes == nullptr && icc_byte_count != 0U)) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_STRUCT_TOO_SMALL;
    }

    const std::span<const std::uint8_t> bytes{
        icc_bytes,
        static_cast<std::size_t>(icc_byte_count)};
    const negaflow::color::SoftProofMedia media =
        negaflow::color::read_soft_proof_media(bytes);
    const negaflow::color::SoftProofPaper paper =
        negaflow::color::soft_proof_paper(media);

    const std::uint32_t declared_size = result->struct_size;
    std::memset(result, 0, sizeof(*result));
    result->struct_size = declared_size;
    result->is_rgb_output_profile =
        negaflow::color::is_rgb_output_profile(bytes) ? 1U : 0U;
    result->has_white = media.has_white ? 1U : 0U;
    result->has_black = media.has_black ? 1U : 0U;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        result->paper_white_rgb[channel] = static_cast<float>(paper.white[channel]);
        result->black_ink_rgb[channel] = static_cast<float>(paper.black[channel]);
    }
    return NF_STATUS_OK;
}
