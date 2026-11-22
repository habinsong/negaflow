#include "negaflow/abi/display_color.h"

#include "negaflow/imaging/display_color_lut.h"

#include <cstdint>
#include <new>
#include <span>

// 미리보기 캔버스의 화면 색관리입니다. 표는 프로파일을 고를 때 한 번 만들고, 화소는 그릴
// 때마다 그 표로 옮깁니다.

struct nf_display_color_transform_v1 final {
    negaflow::imaging::DisplayColorLut lut{};
};

namespace {

nf_status_t create_transform(
    const uint8_t* const icc,
    const uint32_t icc_size,
    const bool round_trip,
    nf_display_color_transform_v1** const transform,
    uint32_t* const is_identity,
    uint32_t* const native_error_code) {
    if (transform == nullptr || is_identity == nullptr || native_error_code == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *transform = nullptr;
    *is_identity = 0U;
    *native_error_code = 0U;
    if (icc == nullptr || icc_size < 128U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    auto* const created = new (std::nothrow) nf_display_color_transform_v1{};
    if (created == nullptr) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    std::uint32_t error = 0U;
    if (!created->lut.build(std::span<const std::uint8_t>(icc, icc_size), error, round_trip)) {
        delete created;
        *native_error_code = error;
        return NF_STATUS_INVALID_ARGUMENT;
    }
    *is_identity = created->lut.identity() ? 1U : 0U;
    *transform = created;
    return NF_STATUS_OK;
}

}  // namespace

nf_status_t NF_CALL nf_proof_color_transform_create_v1(
    const uint8_t* const proof_icc,
    const uint32_t proof_icc_size,
    nf_display_color_transform_v1** const transform,
    uint32_t* const is_identity,
    uint32_t* const native_error_code) {
    return create_transform(
        proof_icc, proof_icc_size, true, transform, is_identity, native_error_code);
}

nf_status_t NF_CALL nf_display_color_transform_create_v1(
    const uint8_t* const monitor_icc,
    const uint32_t monitor_icc_size,
    nf_display_color_transform_v1** const transform,
    uint32_t* const is_identity,
    uint32_t* const native_error_code) {
    return create_transform(
        monitor_icc, monitor_icc_size, false, transform, is_identity, native_error_code);
}

nf_status_t NF_CALL nf_display_color_transform_apply_bgra_v1(
    const nf_display_color_transform_v1* const transform,
    const uint8_t* const source,
    uint8_t* const destination,
    const uint32_t width,
    const uint32_t height,
    const uint32_t stride_bytes) {
    if (transform == nullptr || source == nullptr || destination == nullptr || width == 0U ||
        height == 0U || static_cast<std::uint64_t>(stride_bytes) < static_cast<std::uint64_t>(width) * 4ULL) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    transform->lut.apply_bgra(source, stride_bytes, destination, stride_bytes, width, height);
    return NF_STATUS_OK;
}

void NF_CALL nf_display_color_transform_destroy_v1(nf_display_color_transform_v1* const transform) {
    delete transform;
}
