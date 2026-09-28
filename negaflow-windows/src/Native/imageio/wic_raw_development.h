#pragma once

#include "negaflow/imageio/wic_standard_image_decoder.h"

#include <Windows.h>
#include <wincodec.h>

#include <filesystem>

namespace negaflow::imageio::wic_detail {

// RAW 프레임을 촬영 설정(as-shot)·sRGB 로 현상하게 맞춥니다.
//
// 코덱이 `IWICDevelopRaw` 를 아예 내지 않으면 그 확장자를 기억합니다. 파일이 아니라 코덱의
// 성질이라, 같은 확장자는 다시 열어도 같은 자리에서 멈춥니다 - 이 기계의 Raw Image
// Extension 은 CR3 에 72 ms, 69MP DNG 에 123 ms 를 쓰고 매번 여기서 실패했습니다.
[[nodiscard]] WicStandardImageDecodeStatus configure_raw_development(
    IWICImagingFactory* factory,
    IWICBitmapFrameDecode* frame,
    const std::filesystem::path& path) noexcept;

// 이 확장자의 WIC RAW 코덱이 현상 인터페이스를 내지 않는다고 이미 확인했는지입니다.
// 그렇다면 WIC 를 다시 열지 않고 LibRaw 로 곧장 갑니다 - 결과는 WIC 를 거쳐 실패한 뒤와 같습니다.
[[nodiscard]] bool raw_development_known_unavailable(const std::filesystem::path& path) noexcept;

}  // namespace negaflow::imageio::wic_detail
