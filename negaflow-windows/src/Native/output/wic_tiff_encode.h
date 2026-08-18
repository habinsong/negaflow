#pragma once

#include "wic_srgb16_support.h"

#include "negaflow/output/wic_tiff_export.h"

#include <Windows.h>
#include <wincodec.h>

#include <cstdint>

namespace negaflow::output::wic_tiff_detail {

// 우리 압축 선택을 WIC 의 것과 TIFF 태그 값으로 옮깁니다. 모르는 조합이면 false 입니다.
[[nodiscard]] bool map_wic_tiff_compression(
    WicTiffCompression compression,
    BYTE& wic_value,
    std::uint16_t& tiff_tag_value) noexcept;

// 화소를 TIFF 로 굽습니다. 색 문맥·DPI·메타데이터 정책도 여기서 씁니다.
[[nodiscard]] WicTiffExportStatus encode_tiff(
    IWICImagingFactory* factory,
    IStream* stream,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& image,
    IWICColorContext* color_context,
    const WorkingToSrgb16Limits& conversion_limits,
    WicTiffCompression compression,
    std::uint32_t output_dpi,
    std::uint32_t write_buffer_bytes,
    ExportMetadataPolicy metadata_policy,
    const ExportMetadataFields& metadata,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::wic_tiff_detail
