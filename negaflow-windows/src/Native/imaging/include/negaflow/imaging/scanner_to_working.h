#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imageio/decoded_image.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging {

enum class ScannerWorkingTransform : std::uint8_t {
    none = 0,
    linear_scanner_raw,
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
    std::uint64_t max_working_pixel_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint64_t max_temporary_pixel_bytes{512ULL * 1024ULL * 1024ULL};
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
// - an untagged 16-bit TIFF is explicitly interpreted as linear-sRGB scanner raw.
[[nodiscard]] ScannerToWorkingResult convert_scanner_to_working(
    const negaflow::imageio::DecodedImage& decoded,
    const ScannerToWorkingLimits& limits = {}) noexcept;

[[nodiscard]] const char* scanner_to_working_status_name(ScannerToWorkingStatus status) noexcept;
[[nodiscard]] const char* scanner_working_transform_name(ScannerWorkingTransform transform) noexcept;

}  // namespace negaflow::imaging
