#pragma once

#include "negaflow/color/icc_profile.h"
#include "negaflow/imageio/decoded_image.h"

#include "negaflow/core/machine_memory.h"

#include <cstdint>
#include <filesystem>
#include <stop_token>

namespace negaflow::imageio {

// `libraw_image_decoder.h` 는 **이 헤더의** 타입을 쓰므로 여기서 그것을 include 하면
// 순환이 됩니다. 여기서 필요한 것은 열거형 하나뿐이고, 밑수를 못박아 둔 덕에 앞서
// 선언만 해도 값으로 담을 수 있습니다.
enum class LibRawDecodeStatus : std::uint8_t;

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
    // LibRaw 대체를 **불러 보기는 했는지**, 그리고 그것이 내놓은 판정입니다.
    //
    // LibRaw 가 실패하면 호출자에게는 WIC 의 사유가 그대로 돌아갑니다(그래야 "codec 없음"
    // 과 "파일 깨짐" 이 안 섞입니다). 그 바람에 **LibRaw 의 사유는 여태 그 자리에서
    // 사라졌습니다** — 같은 파일이 한 기계에서만 안 열릴 때 LibRaw 가 무엇을 보고
    // 물러났는지 알 길이 없었습니다(QA 2026-08-31 펜탁스 K-1 DNG). 사용자에게 보이는
    // 판정은 건드리지 않고, 진단만 여기 실어 보냅니다.
    // 열거형이 아직 불완전해 `LibRawDecodeStatus::ok` 라고 적을 수 없어 값 초기화를 씁니다
    // (`ok` 가 0 입니다). 이 값이 뜻을 갖는 것은 `libraw_attempted` 가 true 일 때뿐입니다.
    bool libraw_attempted{false};
    LibRawDecodeStatus libraw_status{};
    int libraw_native_error_code{0};
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

/// 파일에 적힌 **촬영 기록**입니다. 필름 카메라는 EXIF 를 남기지 않으므로 스캔 원본에는
/// 없고, 사용자가 가져온 디지털 원본에만 있습니다.
///
/// macOS 는 `SourceMetadataReader` 가 `CGImageSourceCopyPropertiesAtIndex` 로 읽어
/// `SourceEXIFMetadata` 에 담고, 현상 인스펙터 머리줄이 그 값을 씁니다. 이것이 그 짝입니다 —
/// 값이 없으면 `has_*` 가 false 이고, 화면은 그 자리에 `—` 를 냅니다.
struct SourceShotMetadata final {
    bool has_iso_speed{false};
    std::uint32_t iso_speed{0U};
    bool has_exposure_time{false};
    double exposure_time_seconds{0.0};
    bool has_f_number{false};
    double f_number{0.0};
    bool has_focal_length{false};
    double focal_length_mm{0.0};

    [[nodiscard]] bool empty() const noexcept {
        return !has_iso_speed && !has_exposure_time && !has_f_number && !has_focal_length;
    }
};

struct SourceShotMetadataResult final {
    StandardImageMetadataStatus status{StandardImageMetadataStatus::invalid_argument};
    SourceShotMetadata shot{};
    bool libraw_fallback_used{false};
};

/// 화소를 만들지 않고 EXIF 촬영 태그만 읽습니다.
///
/// `probe_standard_image_metadata` 와 나란한 자리이지만 **가져오기 경로에서는 부르지
/// 않습니다** — 가져오기는 크기만 있으면 되고, 여기는 화면이 한 장을 열 때만 봅니다.
/// 컨테이너를 JPEG/PNG/RAW 으로 좁히지 않습니다: 태그만 읽으므로 WIC 가 여는 파일이면
/// 무엇이든 읽을 수 있어야 합니다(가져온 TIFF 도 포함).
[[nodiscard]] SourceShotMetadataResult probe_source_shot_metadata(
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
