#pragma once

#include <cstdint>
#include <vector>

namespace negaflow::imageio {

enum class DecodedPixelLayout : std::uint8_t {
    rgb16 = 0,
    rgba16,
    gray16,
};

enum class AlphaMode : std::uint8_t {
    opaque = 0,
    associated,
    unassociated,
};

// TIFF scanner captures without an ICC profile are linear sensor data. Standard desktop
// images without an embedded profile follow the WIC/sRGB convention instead.
enum class UntaggedRgbTransfer : std::uint8_t {
    linear_scanner = 0,
    srgb_encoded,
};

struct DecodedImage final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_bytes{0};
    DecodedPixelLayout layout{DecodedPixelLayout::rgb16};
    AlphaMode alpha_mode{AlphaMode::opaque};
    UntaggedRgbTransfer untagged_rgb_transfer{UntaggedRgbTransfer::linear_scanner};
    std::vector<std::uint16_t> samples{};
    std::vector<std::uint8_t> icc_profile{};
};

[[nodiscard]] std::uint8_t channel_count(DecodedPixelLayout layout) noexcept;
[[nodiscard]] const char* decoded_pixel_layout_name(DecodedPixelLayout layout) noexcept;
[[nodiscard]] const char* alpha_mode_name(AlphaMode mode) noexcept;

}  // namespace negaflow::imageio
