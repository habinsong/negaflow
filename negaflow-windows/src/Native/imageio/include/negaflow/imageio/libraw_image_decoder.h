#pragma once

#include "negaflow/imageio/decoded_image.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <cstdint>
#include <filesystem>
#include <stop_token>

namespace negaflow::imageio {

/// 설치된 WIC codec 이 카메라 RAW 을 못 읽을 때 쓰는 대체 디코더입니다.
///
/// **왜 필요한가.** Microsoft 공식 WIC 문서가 기본 제공이라고 적은 codec 은 BMP·GIF·ICO·
/// JPEG·JPEG XR·PNG·TIFF·HD Photo·DDS 아홉 개뿐이고 **RAW 은 없습니다.** RAW 은 Microsoft
/// Store 의 별도 무료 패키지 `Raw Image Extension` 이며 선탑재가 보장되지 않습니다.
/// macOS 는 ImageIO 에 RAW 디코더가 들어 있어 맥 사용자는 이 문제를 겪지 않으므로, 같은
/// 파일이 맥에서는 열리고 Windows 에서만 안 열리는 parity 결함이 됩니다.
///
/// **어떻게 채우는가.** LibRaw 를 `libraw.dll` 로 함께 배포하고 `LoadLibrary` 로 실행 중에
/// 엽니다. native 엔진은 LibRaw 를 **링크하지 않습니다** — 심볼을 실행 중에 찾습니다.
/// LibRaw 는 LGPL-2.1 / CDDL-1.0 이중 라이선스이고 LGPL-2.1 은 다른 라이선스의 프로그램이
/// 동적으로 링크하는 것을 허용합니다. GPL 인 SANE 백엔드를 별도 프로세스로 뺀 것과 달리
/// 프로세스 경계가 필요하지 않은 이유가 이것입니다.
///
/// **결과 계약은 WIC RAW 경로와 같습니다.** `rgba16` · unassociated alpha ·
/// `srgb_encoded` 전달 함수 · EXIF orientation 1(디코더가 이미 회전을 적용함). WIC 가
/// `WICAsShotParameterSet` 으로 촬영 당시 화이트밸런스를 쓰므로 여기서도 카메라의
/// `cam_mul` 을 그대로 씁니다. 자동 밝기 보정은 양쪽 다 끕니다.
enum class LibRawDecodeStatus : std::uint8_t {
    ok = 0,
    // `libraw.dll` 이 없거나 필요한 심볼이 빠져 있습니다. 이것은 **실패가 아니라 부재**이며
    // 호출자는 원래의 WIC 실패 사유를 그대로 사용자에게 돌려줘야 합니다.
    unavailable,
    invalid_argument,
    open_failed,
    unpack_failed,
    process_failed,
    unsupported_output,
    memory_limit_exceeded,
    allocation_failed,
    cancelled,
};

struct LibRawDecodeResult final {
    LibRawDecodeStatus status{LibRawDecodeStatus::unavailable};
    // LibRaw 가 돌려준 오류 코드입니다. 0 이면 LibRaw 를 부르기 전에 끝난 것입니다.
    int native_error_code{0};
    // 요청한 프리뷰 상자에 맞추느라 이미 줄여서 돌려주었는지입니다. 호출부가 뒤에서
    // 한 번 더 줄이지 않도록 알립니다 - WIC 경로의 `reduced_for_preview` 와 같은 뜻입니다.
    bool reduced_for_preview{false};
    DecodedImage image{};
};

/// 화소를 만들지 않고 **헤더만 읽어** 크기를 돌려줍니다.
struct LibRawMetadataResult final {
    LibRawDecodeStatus status{LibRawDecodeStatus::unavailable};
    int native_error_code{0};
    std::uint32_t pixel_width{0U};
    std::uint32_t pixel_height{0U};
};

/// 가져오기는 가로·세로만 있으면 됩니다. 그것을 알려고 파일 전체를 현상하면 한 장에
/// 수백 MB 와 수 초가 들고, 폴더 단위로는 그대로 무너집니다 - macOS 는 같은 자리에서
/// `CGImageSourceCopyPropertiesAtIndex` 로 속성만 읽습니다. 이것이 그 짝입니다.
[[nodiscard]] LibRawMetadataResult probe_raw_metadata_with_libraw(
    const std::filesystem::path& path) noexcept;

/// 화소도 만들지 않고 **촬영 기록만** 읽습니다. `libraw_open_wfile` 이 헤더를 훑으며
/// `imgdata.other` 를 채우므로 `libraw_unpack` 도 `libraw_dcraw_process` 도 부르지 않습니다.
///
/// `libraw_get_imgother` 는 **선택 심볼**입니다. 없는 `libraw.dll` 을 만나면 촬영 기록만
/// 비고 RAW 현상 자체는 그대로 됩니다 — 필수 심볼로 묶으면 옛 DLL 하나 때문에 RAW 을
/// 통째로 못 엽니다.
struct LibRawShotResult final {
    LibRawDecodeStatus status{LibRawDecodeStatus::unavailable};
    SourceShotMetadata shot{};
};

[[nodiscard]] LibRawShotResult probe_raw_shot_with_libraw(
    const std::filesystem::path& path) noexcept;

/// `libraw.dll` 을 열 수 있고 필요한 심볼이 전부 있는지 봅니다. 한 번 확인한 결과를
/// 재사용하며 실패해도 매번 다시 시도하지 않습니다.
[[nodiscard]] bool libraw_decoder_available() noexcept;

/// 이 실행 파일이 실제로 연 `libraw.dll` 의 버전 문자열입니다. 없으면 빈 문자열입니다.
[[nodiscard]] const char* libraw_decoder_version() noexcept;

[[nodiscard]] LibRawDecodeResult decode_raw_with_libraw(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits,
    std::stop_token stop_token = {},
    const WicStandardImageDecodeControl& control = {}) noexcept;

[[nodiscard]] const char* libraw_decode_status_name(LibRawDecodeStatus status) noexcept;

}  // namespace negaflow::imageio
