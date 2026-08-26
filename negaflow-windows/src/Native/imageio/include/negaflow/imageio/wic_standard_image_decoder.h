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

/// 프리뷰가 쓸 최대 크기입니다. 0 이면 원본 그대로 풉니다.
///
/// 스캐너 TIFF 경로의 `WicTiffDecodeControl::max_output_*` 과 같은 자리입니다 - 표준·RAW
/// 경로에만 없어서, 1536x1024 프리뷰 하나에 6000x4000 이상을 통째로 풀고 있었습니다.
struct WicStandardImageDecodeControl final {
    std::uint32_t max_output_width{0U};
    std::uint32_t max_output_height{0U};
    // 프리뷰 프록시를 만드는 길입니다. 정확도보다 시간이 우선입니다.
    bool prefer_speed{false};
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
    // 프리뷰 크기로 줄여 풀었습니다. 캐시가 이것을 전체 해상도 결과와 섞지 않도록 남깁니다.
    bool reduced_for_preview{false};
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

/// 화소를 만들지 않고 **헤더만 읽어** 크기를 돌려줍니다.
enum class StandardImageMetadataStatus : std::uint8_t {
    ok = 0,
    invalid_argument,
    com_apartment_mismatch,
    unreadable,
    unsupported,
};

struct StandardImageMetadata final {
    std::uint32_t pixel_width{0U};
    std::uint32_t pixel_height{0U};
    std::uint16_t exif_orientation{1U};
    bool libraw_fallback_used{false};
};

struct StandardImageMetadataResult final {
    StandardImageMetadataStatus status{StandardImageMetadataStatus::invalid_argument};
    StandardImageMetadata metadata{};
};

/// 가져오기는 가로·세로만 있으면 됩니다.
///
/// **그것을 알려고 파일을 끝까지 현상하면 안 됩니다.** 실측(2026-08-26, 제조사별 RAW 8 장):
/// 크기만 읽는 프로브가 파일당 1~13 초, 8 장에 peak 980 MB 를 썼습니다 — 7168x5120 한 장이
/// RGBA16 으로 294 MB 이고, 그 뒤 전 화소를 훑어 불투명 여부까지 검사한 뒤 전부 버리고
/// 가로·세로만 썼기 때문입니다. 폴더 가져오기가 그 때문에 무너졌습니다.
///
/// macOS 는 같은 자리에서 `CGImageSourceCopyPropertiesAtIndex` 로 속성만 읽습니다
/// (`ImageLoader+ImageIO.swift`의 `sourcePixelSize`). 이것이 그 짝입니다 — WIC 는 프레임을
/// 열어 `GetSize` 만 부르고, WIC 가 못 여는 카메라 RAW 은 `libraw_open_wfile` 뒤 크기만
/// 읽습니다(`libraw_unpack` 도 `dcraw_process` 도 부르지 않습니다).
[[nodiscard]] StandardImageMetadataResult probe_standard_image_metadata(
    const std::filesystem::path& path) noexcept;

/// WIC codec 만 씁니다. LibRaw 대체 없이 WIC 자체의 판정을 보고 싶은 시험이 씁니다.
[[nodiscard]] WicStandardImageDecodeResult decode_standard_image_with_wic_only(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits = {},
    std::stop_token stop_token = {},
    const WicStandardImageDecodeControl& control = {}) noexcept;

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
    std::stop_token stop_token = {},
    const WicStandardImageDecodeControl& control = {}) noexcept;

[[nodiscard]] const char* wic_standard_image_decode_status_name(
    WicStandardImageDecodeStatus status) noexcept;

}  // namespace negaflow::imageio
