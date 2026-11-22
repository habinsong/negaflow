#pragma once

#include "negaflow/imaging/scanner_to_working.h"

#include "negaflow/color/output_color_space.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/pixel.h"

#include <cstdint>
#include <span>
#include <vector>

namespace negaflow::imaging::detail {

struct EncodedSrgb16Result final {
    ScannerToWorkingStatus status{ScannerToWorkingStatus::invalid_argument};
    std::uint32_t native_error_code{0};
    std::vector<std::uint16_t> samples{};
};

[[nodiscard]] ScannerToWorkingStatus validate_scanner_icc_profile(
    std::span<const std::uint8_t> profile_bytes,
    const ScannerToWorkingLimits& limits,
    negaflow::color::IccProfileStatus& icc_status,
    ScannerToWorkingInfo& info) noexcept;

[[nodiscard]] ScannerToWorkingStatus convert_linear_scanner_raw(
    const negaflow::imageio::DecodedImage& decoded,
    WorkingImage& output);

// 임베디드 ICC 입력을 옮기는 내부 중간 공간 프로파일입니다(Rec.2020 기본색, sRGB 곡선).
// 한 번 만들어 둡니다. 만들지 못했으면 빈 범위이며, 그때 입력 변환은 실패합니다 — 조용히
// sRGB 로 옮기면 해독이 다른 공간을 가정해 색이 틀어집니다.
[[nodiscard]] std::span<const std::uint8_t> working_intermediate_profile() noexcept;

// 데이터 공간이 'GRAY' 인 프로파일인지입니다(머리말만 봅니다).
[[nodiscard]] inline bool icc_is_gray(const std::span<const std::uint8_t> profile) noexcept {
    return profile.size() >= 20U && profile[16] == 'G' && profile[17] == 'R' &&
           profile[18] == 'A' && profile[19] == 'Y';
}

// 중간 공간 16비트 표본 → 선형 sRGB 기본색 작업 화소입니다. 음수·1 초과를 그대로 둡니다 —
// macOS 가 원본 색공간에서 선형 확장 작업 공간으로 옮길 때와 같습니다.
struct IntermediateToWorking final {
    std::span<const float, 65536U> linear{negaflow::color::srgb16_to_linear_table()};
    negaflow::color::ColorMatrix matrix{negaflow::color::working_intermediate_to_linear_srgb()};

    [[nodiscard]] negaflow::core::Rgba32F operator()(
        const std::uint16_t red,
        const std::uint16_t green,
        const std::uint16_t blue,
        const float alpha) const noexcept {
        const float r = linear[red];
        const float g = linear[green];
        const float b = linear[blue];
        return {
            (matrix[0] * r) + (matrix[1] * g) + (matrix[2] * b),
            (matrix[3] * r) + (matrix[4] * g) + (matrix[5] * b),
            (matrix[6] * r) + (matrix[7] * g) + (matrix[8] * b),
            alpha,
        };
    }
};

// 표본은 중간 공간(`working_intermediate_profile`)으로 옮겨진 값입니다. 이름은 호출부를
// 그대로 두려고 남겼습니다.
[[nodiscard]] EncodedSrgb16Result convert_embedded_icc_to_srgb16(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits,
    std::span<const std::uint8_t> profile_override = {},
    std::span<const std::uint16_t> sample_table = {}) noexcept;

}  // namespace negaflow::imaging::detail
