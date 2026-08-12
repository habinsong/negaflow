#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/imageio/decoded_image.h"

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
    unsupported_pixel_format,
    color_context_failed,
    invalid_icc_profile,
    memory_limit_exceeded,
    allocation_failed,
    pixel_decode_failed,
};

struct WicStandardImageDecodeLimits final {
    negaflow::color::IccProfileLimits icc{};
    std::uint64_t max_decoded_pixel_bytes{512ULL * 1024ULL * 1024ULL};
    std::uint32_t max_color_contexts{4U};
};

struct WicStandardImageDecodeInfo final {
    std::uint32_t frame_count{0U};
    std::uint64_t decoded_pixel_bytes{0U};
    bool format_conversion_used{false};
    negaflow::color::IccProfileInfo icc{};
};

struct WicStandardImageDecodeResult final {
    WicStandardImageDecodeStatus status{WicStandardImageDecodeStatus::invalid_argument};
    negaflow::color::IccProfileStatus icc_status{
        negaflow::color::IccProfileStatus::not_present};
    WicStandardImageDecodeInfo info{};
    DecodedImage image{};
};

// Decodes only WIC's built-in JPEG and PNG containers. Untagged values are explicitly
// marked as sRGB, while embedded RGB ICC profiles remain attached for Windows ICM.
[[nodiscard]] WicStandardImageDecodeResult decode_standard_image_with_wic(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits = {},
    std::stop_token stop_token = {}) noexcept;

[[nodiscard]] const char* wic_standard_image_decode_status_name(
    WicStandardImageDecodeStatus status) noexcept;

}  // namespace negaflow::imageio
