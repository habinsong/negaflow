#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/imageio/decoded_image.h"

#include "negaflow/core/machine_memory.h"

#include <cstdint>
#include <filesystem>
#include <stop_token>

namespace negaflow::imageio {

enum class WicStandardImageDecodeStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    cancelled,
    com_apartment_mismatch,
    wic_unavailable,
    decoder_initialization_failed,
    unsupported_container,
    frame_count_unsupported,
    raw_development_failed,
    unsupported_pixel_format,
    color_context_failed,
    invalid_icc_profile,
    memory_limit_exceeded,
    allocation_failed,
    pixel_decode_failed,
};

struct WicStandardImageDecodeLimits final {
    negaflow::color::IccProfileLimits icc{};
    // 이 기계의 설치 메모리에서 옵니다 - `negaflow::core::default_max_pixel_bytes` 주석 참고.
    std::uint64_t max_decoded_pixel_bytes{negaflow::core::default_max_pixel_bytes()};
    std::uint32_t max_color_contexts{4U};
};

struct WicStandardImageDecodeInfo final {
    std::uint32_t frame_count{0U};
    std::uint64_t decoded_pixel_bytes{0U};
    bool format_conversion_used{false};
    bool raw_development_used{false};
    // 설치된 WIC codec 이 이 파일을 열지 못해 함께 배포한 `libraw.dll` 이 대신 현상했습니다.
    // 진단이 어느 디코더가 화소를 만들었는지 구분할 수 있어야 하므로 남깁니다.
    bool libraw_fallback_used{false};
    std::uint16_t exif_orientation{1U};
    bool orientation_applied{false};
    negaflow::color::IccProfileInfo icc{};
};

struct WicStandardImageDecodeResult final {
    WicStandardImageDecodeStatus status{WicStandardImageDecodeStatus::invalid_argument};
    negaflow::color::IccProfileStatus icc_status{
        negaflow::color::IccProfileStatus::not_present};
    WicStandardImageDecodeInfo info{};
    DecodedImage image{};
};

/// WIC codec 만 씁니다. LibRaw 대체 없이 WIC 자체의 판정을 보고 싶은 시험이 씁니다.
[[nodiscard]] WicStandardImageDecodeResult decode_standard_image_with_wic_only(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits = {},
    std::stop_token stop_token = {}) noexcept;

/// JPEG/PNG 과 카메라 RAW 을 읽습니다. WIC RAW codec 이 있으면 그것이 as-shot·최고 품질
/// sRGB 현상을 하고, **없으면 함께 배포한 `libraw.dll` 이 같은 계약으로 대신 현상합니다.**
/// Windows 는 RAW codec 을 기본 제공하지 않으므로(Store 의 별도 패키지) 이 대체가 없으면
/// 같은 파일이 macOS 에서는 열리고 Windows 에서만 안 열립니다.
///
/// 태그 없는 JPEG/PNG 값은 명시적으로 sRGB 로 표시하고, 박힌 RGB ICC 프로필은 Windows ICM
/// 을 위해 그대로 붙여 둡니다.
[[nodiscard]] WicStandardImageDecodeResult decode_standard_image_with_wic(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits = {},
    std::stop_token stop_token = {}) noexcept;

[[nodiscard]] const char* wic_standard_image_decode_status_name(
    WicStandardImageDecodeStatus status) noexcept;

}  // namespace negaflow::imageio
