#pragma once

#include "wic_srgb16_support.h"

#include "negaflow/core/tiff_probe.h"
#include "negaflow/output/wic_tiff_export.h"

#include <Windows.h>
#include <wincodec.h>

#include <cstdint>
#include <filesystem>
#include <vector>

namespace negaflow::output::wic_tiff_detail {

// 쓴 파일을 다시 읽어 화소·프로파일이 의도한 것과 같은지 확인합니다. 여기서 걸리면
// 게시하지 않습니다 - 못 읽는 파일을 목적지에 남기는 것보다 실패로 끝나는 편이 낫습니다.
[[nodiscard]] WicTiffExportStatus verify_tiff_readback(
    IWICImagingFactory* factory,
    const std::filesystem::path& path,
    const negaflow::imaging::WorkingImage& working,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const WicTiffExportLimits& limits,
    WorkingToSrgb16Status& conversion_status,
    std::uint32_t& native_error_code);

// probe 가 읽은 배치가 우리가 쓴 것과 같은지 확인합니다. 화소를 읽지 않고 태그만 봅니다.
[[nodiscard]] bool validate_tiff_structure(
    const negaflow::core::TiffProbeResult& probe,
    const Srgb16Image& expected,
    std::uint16_t expected_compression,
    std::uint32_t expected_profile_bytes) noexcept;

}  // namespace negaflow::output::wic_tiff_detail
