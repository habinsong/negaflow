#pragma once

#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>
#include <wincodec.h>

#include <cstdint>

namespace negaflow::imageio::wic_tiff_detail {

// 화소 소스에서 행을 떠 옵니다. `row_sink` 가 null 이면 결과 버퍼에 통째로 담고, 아니면
// 한 덩이씩 sink 에 넘겨 프레임 전체를 붙잡지 않습니다.
//
// `sink_started` 는 호출부와 나눠 씁니다 - 예외로 빠져나가도 호출부가 sink 를 닫을 수 있어야
// 하기 때문입니다. sink 를 연 뒤에는 이 함수가 실패 경로에서 스스로 닫고 false 로 되돌립니다.
[[nodiscard]] WicTiffDecodeStatus copy_tiff_rows(
    IWICBitmapSource* pixel_source,
    std::uint64_t stride_bytes,
    std::uint64_t pixel_bytes,
    UINT width,
    UINT height,
    const WicTiffDecodeControl& control,
    WicTiffRowSink* row_sink,
    bool& sink_started,
    WicTiffDecodeResult& result);

}  // namespace negaflow::imageio::wic_tiff_detail
