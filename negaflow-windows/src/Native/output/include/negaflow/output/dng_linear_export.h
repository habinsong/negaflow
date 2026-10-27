#pragma once

#include "negaflow/color/output_color_space.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/output/export_metadata.h"
#include "negaflow/output/working_to_srgb16.h"

#include <cstdint>
#include <filesystem>

namespace negaflow::output {

// 현상한 화상을 16비트 선형 RGB DNG(PhotometricInterpretation = LinearRaw)로 게시합니다.
// macOS `DNGLinearWriter` 와 같은 파일을 씁니다.
//
// 이 코드는 Adobe DNG 규격 1.6 에 적힌 태그 번호·의미만 보고 새로 작성했습니다. Adobe DNG SDK,
// LibRaw, 다른 DNG 기록기의 코드는 보거나 옮기지 않았습니다. DNG 는 Adobe 의 등록 상표이며
// 이 앱은 규격이 공개한 파일 형식을 쓸 뿐입니다(docs/legal/PROVENANCE.md).
//
// This product includes DNG technology under license by Adobe.
//
// - 화소: 고른 출력 색공간(sRGB · Display P3 · Adobe RGB)의 선형 값 16비트 3채널. 톤·색은 현상에서
//   이미 구워져 있습니다(장면 기준이 아니라 출력 기준 데이터).
// - 색 해석: ColorMatrix1(XYZ → 그 공간의 RGB) · AsShotNeutral(1,1,1) · CalibrationIlluminant1(D65).
// - 압축: 16비트 정수 LinearRaw 에 쓸 수 있는 DNG 압축은 무손실 JPEG 뿐이라 무압축입니다.
// - 메타데이터: 저작권, 스캐너·소프트웨어·날짜, 필름 기록만 담습니다. 원본 카메라 EXIF·IPTC·GPS
//   전체는 옮기지 않습니다.
enum class DngExportStatus : std::uint8_t {
    ok = 0,
    working_conversion_failed,
    allocation_failed,
    size_limit_exceeded,
    destination_exists,
    staging_create_failed,
    write_failed,
    flush_failed,
    structure_verification_failed,
    publish_failed,
    published_file_invalid,
};

struct DngExportLimits final {
    // 색공간을 정하고 값을 선형 그대로 둡니다(`encode_transfer` 는 이 함수가 꺼서 씁니다).
    WorkingToSrgb16Limits conversion{};
    negaflow::color::OutputColorSpace color_space{negaflow::color::OutputColorSpace::srgb};
    // 0 이면 해상도를 적지 않습니다. 양수는 메타데이터일 뿐입니다.
    std::uint32_t output_dpi{0U};
    // 32비트 TIFF 오프셋으로 표현할 수 있는 파일 크기의 안전 한도입니다.
    std::uint64_t max_artifact_bytes{4'000'000'000ULL};
    // 줄 묶음(strip) 하나의 목표 크기. 변환·쓰기 단위이자 메모리 상한입니다.
    std::uint32_t strip_bytes{4U * 1024U * 1024U};
    ExportMetadataPolicy metadata_policy{ExportMetadataPolicy::minimal};
    ExportMetadataFields metadata{};
};

struct DngExportInfo final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t artifact_bytes{0U};
    std::uint64_t strip_count{0U};
    std::uint64_t clipped_color_components{0U};
    bool published{false};
};

struct DngExportResult final {
    DngExportStatus status{DngExportStatus::working_conversion_failed};
    WorkingToSrgb16Status conversion_status{WorkingToSrgb16Status::invalid_dimensions};
    DngExportInfo info{};
    std::uint32_t native_error_code{0U};
    std::uint32_t cleanup_error_code{0U};
};

[[nodiscard]] DngExportResult export_working_to_dng16(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const DngExportLimits& limits = {}) noexcept;

[[nodiscard]] const char* dng_export_status_name(DngExportStatus status) noexcept;

}  // namespace negaflow::output
