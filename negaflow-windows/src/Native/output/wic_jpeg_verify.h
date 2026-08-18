#pragma once

#include "wic_srgb16_support.h"

#include "negaflow/output/wic_jpeg_export.h"

#include <Windows.h>
#include <wincodec.h>

#include <cstdint>
#include <filesystem>
#include <vector>

namespace negaflow::output::wic_jpeg_detail {

// 쓴 파일에서 읽어 낸 JPEG 의 뼈대입니다.
struct JpegStructure final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint8_t components{0U};
    std::uint8_t chroma_subsampling{0U};
};

// 파일 바이트를 직접 훑어 SOF 세그먼트에서 뼈대를 읽습니다. 디코더를 다시 세우지 않으므로
// 인코더가 무엇을 썼는지 그대로 봅니다.
[[nodiscard]] bool inspect_jpeg_structure(
    const std::filesystem::path& path,
    std::uint64_t maximum_file_bytes,
    JpegStructure& result) noexcept;

// 쓴 파일을 다시 읽어 치수·프로파일·DPI 가 의도한 것과 같은지 확인합니다. 여기서 걸리면
// 게시하지 않습니다 - 못 읽는 파일을 목적지에 남기는 것보다 실패로 끝나는 편이 낫습니다.
[[nodiscard]] WicJpegExportStatus verify_jpeg_readback(
    IWICImagingFactory* factory,
    const std::filesystem::path& path,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    std::uint32_t dpi,
    WicJpegExportInfo& info,
    std::uint32_t& native_error_code) noexcept;

}  // namespace negaflow::output::wic_jpeg_detail
