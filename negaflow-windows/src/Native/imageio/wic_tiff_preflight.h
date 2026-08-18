#pragma once

#include "negaflow/imageio/wic_tiff_decoder.h"

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>
#include <wrl/client.h>

#include <cstdint>
#include <filesystem>

namespace negaflow::imageio::wic_tiff_detail {

// 디코드에 들어가기 전에 확정한 것들입니다. 스트림은 이후 단계가 계속 읽으므로 여기서
// 소유를 넘깁니다.
struct TiffPreflight final {
    Microsoft::WRL::ComPtr<IStream> stream{};
    negaflow::core::TiffProbeInfo info{};
    std::uint64_t stride_bytes{0U};
    std::uint64_t pixel_bytes{0U};
};

// 파일을 열고, TIFF 를 검사하고, 이 디코더가 다룰 배치인지와 메모리 한계를 판정한 뒤
// 스트림을 되감습니다. 압축 TIFF 면 코드 스트림까지 한 번 더 검사합니다.
//
// ok 를 내면 `preflight` 가 채워집니다. 그 밖의 값은 실패이며 이유는 반환값 자체이고,
// 진단 수치는 `result` 에 이미 적혀 있습니다.
[[nodiscard]] WicTiffDecodeStatus preflight_tiff_source(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control,
    TiffPreflight& preflight,
    WicTiffDecodeResult& result);

}  // namespace negaflow::imageio::wic_tiff_detail
