#pragma once

#include "atomic_output_file.h"
#include "wic_srgb16_support.h"

#include "negaflow/output/wic_jpeg_export.h"

#include <Windows.h>
#include <wincodec.h>

#include <cstdint>
#include <vector>

namespace negaflow::output::wic_jpeg_detail {

[[nodiscard]] WicJpegExportStatus map_atomic_status(
    detail::AtomicOutputStatus status) noexcept;

// 실패했을 때 임시 파일을 지웁니다. 반쯤 쓴 파일이 목적지에 남지 않게 합니다.
void discard_staging(
    detail::AtomicOutputFile* output,
    WicJpegExportResult& result) noexcept;

// 인코더 옵션 하나를 씁니다. 이름이 없는 옵션은 실패로 봅니다 - 조용히 무시되면 품질이
// 지정한 값과 달라진 채로 나갑니다.
[[nodiscard]] bool write_option(
    IPropertyBag2* options,
    const wchar_t* name,
    const VARIANT& value) noexcept;

// 화소를 JPEG 로 굽습니다. 색 문맥·DPI·메타데이터 정책도 여기서 씁니다.
[[nodiscard]] WicJpegExportStatus encode_jpeg(
    IWICImagingFactory* factory,
    IStream* stream,
    const Srgb16Image& image,
    IWICColorContext* color_context,
    float quality,
    std::uint32_t dpi,
    std::uint8_t expected_subsampling,
    ExportMetadataPolicy metadata_policy,
    const ExportMetadataFields& metadata,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::wic_jpeg_detail
