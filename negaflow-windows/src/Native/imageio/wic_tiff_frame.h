#pragma once

#include "wic_tiff_preflight.h"

#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

namespace negaflow::imageio::wic_tiff_detail {

// probe 가 고른 디렉터리에 대응하는 WIC 프레임과, 그 프레임을 어느 형식으로 낼지입니다.
struct SelectedFrame final {
    Microsoft::WRL::ComPtr<IWICImagingFactory> factory{};
    Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> frame{};
    GUID source_format{};
    GUID target_format{};
    UINT width{0U};
    UINT height{0U};
};

// WIC 디코더를 세우고 probe 가 고른 디렉터리와 치수가 맞는 프레임을 하나만 고릅니다.
//
// 프레임 번호가 디렉터리 번호와 같다고 가정하지 않습니다 - WIC 는 축소본 페이지를 프레임으로
// 내놓지 않아서 디렉터리 두 개짜리 Photoshop 스캔이 프레임 하나로 옵니다. 치수로 맞추면
// 어느 쪽이든 맞고, 정확히 하나만 맞기를 요구하면 애매한 파일이 조용히 엉뚱한 페이지를
// 디코드하는 일이 없습니다.
//
// 성공하면 `result` 의 프레임 수·화소 형식·출력 배치(layout/alpha)도 함께 채웁니다.
[[nodiscard]] WicTiffDecodeStatus select_tiff_frame(
    const TiffPreflight& preflight,
    const WicTiffDecodeLimits& limits,
    SelectedFrame& selected,
    WicTiffDecodeResult& result);

// 고른 프레임을 목표 형식의 화소 소스로 바꾸고 ICC 프로파일을 읽습니다. 형식이 이미 같으면
// 변환기를 세우지 않습니다.
[[nodiscard]] WicTiffDecodeStatus open_pixel_source(
    const SelectedFrame& selected,
    const TiffPreflight& preflight,
    const WicTiffDecodeLimits& limits,
    Microsoft::WRL::ComPtr<IWICBitmapSource>& pixel_source,
    WicTiffDecodeResult& result);

}  // namespace negaflow::imageio::wic_tiff_detail
