#pragma once

#include <array>
#include <cmath>
#include <optional>
#include <cstddef>
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

using CameraToWorkingMatrix = std::array<float, 9>;

[[nodiscard]] inline bool valid_camera_matrix(const CameraToWorkingMatrix& m) noexcept {
    for (const float value : m) { if (!std::isfinite(value)) { return false; } }
    const double determinant = static_cast<double>(m[0]) * (m[4] * m[8] - m[5] * m[7]) -
        static_cast<double>(m[1]) * (m[3] * m[8] - m[5] * m[6]) +
        static_cast<double>(m[2]) * (m[3] * m[7] - m[4] * m[6]);
    return std::isfinite(determinant) && std::abs(determinant) > 1.0e-8;
}

struct DecodedImage final {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::uint32_t stride_bytes{0};
    DecodedPixelLayout layout{DecodedPixelLayout::rgb16};
    AlphaMode alpha_mode{AlphaMode::opaque};
    UntaggedRgbTransfer untagged_rgb_transfer{UntaggedRgbTransfer::linear_scanner};
    std::vector<std::uint16_t> samples{};
    std::vector<std::uint8_t> icc_profile{};
    // Native camera RGB. The matrix is deferred until after negative inversion.
    std::optional<CameraToWorkingMatrix> camera_to_working{};
};

/// 화소 하나 안에서 R·G·B 를 읽을 표본 위치입니다.
///
/// 회색(1채널) 원본은 한 표본을 세 채널에 그대로 복제합니다. macOS 는 `CIImage(cgImage:)`
/// 가 회색 CGImage 를 그대로 받아 같은 결과를 냅니다. 변환 loop 마다 `+1U`/`+2U` 를 직접
/// 적으면 gray 에서 **이웃 화소**를 R·G·B 로 읽으므로, 이 표를 공유해서 그 실수를 막습니다.
struct RgbSampleOffsets final {
    std::size_t red{0};
    std::size_t green{1};
    std::size_t blue{2};
};

[[nodiscard]] std::uint8_t channel_count(DecodedPixelLayout layout) noexcept;
[[nodiscard]] RgbSampleOffsets rgb_sample_offsets(DecodedPixelLayout layout) noexcept;
[[nodiscard]] const char* decoded_pixel_layout_name(DecodedPixelLayout layout) noexcept;
[[nodiscard]] const char* alpha_mode_name(AlphaMode mode) noexcept;

}  // namespace negaflow::imageio
