#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imageio/decoded_image.h"

#include "negaflow/core/machine_memory.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging {

enum class ScannerWorkingTransform : std::uint8_t {
    none = 0,
    linear_scanner_raw,
    untagged_srgb_to_linear,
    embedded_icc_windows_icm_srgb16,
};

enum class ScannerToWorkingStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    invalid_dimensions,
    invalid_stride,
    size_overflow,
    buffer_size_mismatch,
    memory_limit_exceeded,
    unsupported_alpha,
    non_opaque_alpha,
    invalid_icc_profile,
    unsupported_icc_color_space,
    unsupported_icc_profile_class,
    color_profile_open_failed,
    color_transform_initialization_failed,
    color_transform_failed,
    allocation_failed,
    cancelled,
};

struct ScannerToWorkingLimits final {
    // 이 기계의 설치 메모리에서 옵니다 - 바이트 상수를 박으면 48MP(768MB)·64MP·128MP
    // 스캔이 32GB 기계에서도 거부됩니다. `negaflow::core::default_max_pixel_bytes` 주석 참고.
    std::uint64_t max_working_pixel_bytes{negaflow::core::default_max_pixel_bytes()};
    std::uint64_t max_temporary_pixel_bytes{negaflow::core::default_max_pixel_bytes()};
    negaflow::color::IccProfileLimits icc{};
};

struct WorkingImage final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_pixels{0};
    std::vector<negaflow::core::Rgba32F> pixels{};
};

struct ScannerToWorkingInfo final {
    ScannerWorkingTransform transform{ScannerWorkingTransform::none};
    std::uint8_t intermediate_bits_per_color_channel{0};
    std::uint32_t native_error_code{0};
    negaflow::color::IccProfileInfo icc{};
};

struct ScannerToWorkingResult final {
    ScannerToWorkingStatus status{ScannerToWorkingStatus::invalid_argument};
    negaflow::color::IccProfileStatus icc_status{
        negaflow::color::IccProfileStatus::not_present};
    ScannerToWorkingInfo info{};
    WorkingImage image{};
};

// Scanner input policy:
// - an embedded RGB ICC profile is honored through Windows ICM color management;
// - untagged scanner TIFF is explicitly interpreted as linear-sRGB scanner raw;
// - untagged standard desktop images are decoded as sRGB.
[[nodiscard]] ScannerToWorkingResult convert_scanner_to_working(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits = {}) noexcept;

[[nodiscard]] const char* scanner_to_working_status_name(ScannerToWorkingStatus status) noexcept;
[[nodiscard]] const char* scanner_working_transform_name(ScannerWorkingTransform transform) noexcept;

}  // namespace negaflow::imaging
