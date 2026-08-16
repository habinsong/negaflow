#pragma once

#include <wincodec.h>

#include <cstdint>
#include <string>

namespace negaflow::output {

/// 게시하는 파일에 무엇을 적을지. macOS `ExportMetadataPolicy` 와 같은 네 값이다.
enum class ExportMetadataPolicy : std::uint8_t {
    /// 원본에서 가져온 것은 아무것도 싣지 않는다. 앱이 아는 것(스캐너·소프트웨어·날짜·
    /// 필름 종류)만 적는다. macOS 기본값이다.
    minimal = 0,
    /// 저작권 표시만 남긴다. 스캐너나 소프트웨어 이름도 적지 않는다.
    copyright_only = 1,
    /// 원본 메타데이터를 싣되 장소를 지운다.
    remove_location = 2,
    /// 원본 메타데이터를 그대로 싣는다.
    all = 3,
};

/// 앱이 아는 값들. 비어 있는 항목은 쓰지 않는다.
struct ExportMetadataFields final {
    std::wstring make;
    std::wstring model;
    std::wstring software;
    std::wstring artist;
    std::wstring copyright;
    /// 필름 종류. `minimal` 에서도 적는다 — 장비 사실이지 사용자가 적은 기록이 아니다.
    std::wstring film_type;
    /// 필름 이름. 사용자가 적은 촬영 기록이므로 `minimal` 에서는 적지 않는다.
    std::wstring film_stock;
    /// `yyyy:MM:dd HH:mm:ss` (EXIF 형식, UTC). 비면 날짜를 쓰지 않는다.
    std::wstring captured_at;
    /// 원본 파일. `minimal` 이 아닌 정책에서 여기 실린 메타데이터를 정책대로 걸러 옮긴다.
    /// 비면 원본에서 아무것도 가져오지 않는다.
    std::wstring source_path;
};

/// 컨테이너마다 WIC 질의 경로가 다르다.
enum class ExportMetadataContainer : std::uint8_t {
    tiff = 0,
    jpeg = 1,
};

enum class ExportMetadataStatus : std::uint8_t {
    ok = 0,
    /// 인코더가 메타데이터 쓰기를 지원하지 않는다. 게시를 막지는 않는다.
    unsupported = 1,
    write_failed = 2,
};

/// 프레임을 커밋하기 **전에** 부른다. 픽셀에는 손대지 않는다.
///
/// 기하 변형은 이미 픽셀에 구워져 있으므로 Orientation 은 언제나 1 로 적는다 — 뷰어가
/// 한 번 더 돌리면 그림이 뒤집힌다.
[[nodiscard]] ExportMetadataStatus write_export_metadata(
    IWICBitmapFrameEncode* frame,
    ExportMetadataContainer container,
    ExportMetadataPolicy policy,
    const ExportMetadataFields& fields,
    std::uint32_t& native_error_code) noexcept;

/// 정책 값이 아는 값인가. ABI 검증에서 쓴다.
[[nodiscard]] bool is_known_export_metadata_policy(std::uint32_t value) noexcept;

}  // namespace negaflow::output
