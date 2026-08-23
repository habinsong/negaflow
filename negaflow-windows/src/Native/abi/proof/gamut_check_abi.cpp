#include "negaflow/abi/soft_proof.h"

#include "negaflow/color/gamut_check.h"

#include <cstdint>
#include <cstddef>
#include <new>
#include <vector>

// 출력 색공간이 색역 경고를 지원하는지 묻습니다.

// 화면 화소를 인화지 프로파일로 갔다가 되돌립니다.
nf_status_t NF_CALL nf_soft_proof_convert_bgra_icc_v1(
    uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    const uint8_t* const destination_icc,
    const uint32_t destination_icc_size) {
    if (pixels == nullptr || destination_icc == nullptr || destination_icc_size == 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    return negaflow::color::soft_proof_convert_bgra_icc(
               pixels, width, height, stride_bytes, destination_icc, destination_icc_size)
               ? NF_STATUS_OK
               : NF_STATUS_INVALID_ARGUMENT;
}

// 주어진 ICC 로 색역 밖 화소를 표시합니다.
nf_status_t NF_CALL nf_gamut_check_mask_icc_v1(
    const uint8_t* const pixels,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes,
    const uint8_t* const destination_icc,
    const uint32_t destination_icc_size,
    uint8_t* const mask,
    const uint32_t mask_size) {
    if (pixels == nullptr || mask == nullptr || width == 0U || height == 0U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    if (static_cast<uint64_t>(width) * height > mask_size) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    // ICM 은 BGR 세 바이트를 받습니다. BGRA 에서 알파를 뺀 사본을 만듭니다.
    // ICM 은 행마다 4바이트 경계를 요구합니다. `너비 × 3` 을 그대로 주면 너비가 4의 배수가
    // 아닐 때 행이 밀려, 사진 위쪽 몇 줄만 맞고 아래는 엉뚱한 화소가 표시됩니다.
    const uint32_t packed_stride = ((width * 3U) + 3U) & ~3U;
    std::vector<uint8_t> bgr;
    try {
        bgr.resize(static_cast<size_t>(packed_stride) * height);
    } catch (const std::bad_alloc&) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    for (uint32_t y = 0U; y < height; ++y) {
        const uint8_t* const row = pixels + (static_cast<size_t>(y) * stride_bytes);
        uint8_t* const target = bgr.data() + (static_cast<size_t>(y) * packed_stride);
        for (uint32_t x = 0U; x < width; ++x) {
            target[(x * 3U)] = row[(x * 4U)];
            target[(x * 3U) + 1U] = row[(x * 4U) + 1U];
            target[(x * 3U) + 2U] = row[(x * 4U) + 2U];
        }
    }
    const auto judged = negaflow::color::check_gamut_bgr8_icc(
        bgr.data(), width, height, packed_stride, destination_icc, destination_icc_size);
    if (judged.status != negaflow::color::GamutCheckStatus::ok) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    for (size_t index = 0U; index < judged.out_of_gamut.size(); ++index) {
        mask[index] = judged.out_of_gamut[index];
    }
    return NF_STATUS_OK;
}

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
