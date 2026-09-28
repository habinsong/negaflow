#pragma once

#include "negaflow/imageio/wic_tiff_decoder.h"

#include "negaflow/core/tiff_probe.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>

namespace negaflow::imageio::wic_tiff_detail {

// 같은 파일을 따로 연 화소 소스를 하나 더 냅니다. 스트림·디코더·변환기를 각자 가지므로 여러
// 레인이 동시에 CopyPixels 해도 서로의 읽기 위치를 건드리지 않습니다. 못 열면 null 입니다.
class WicTiffLaneOpener {
public:
    WicTiffLaneOpener() noexcept = default;
    WicTiffLaneOpener(const WicTiffLaneOpener&) = delete;
    WicTiffLaneOpener& operator=(const WicTiffLaneOpener&) = delete;
    virtual ~WicTiffLaneOpener() = default;

    [[nodiscard]] virtual Microsoft::WRL::ComPtr<IWICBitmapSource> open() const noexcept = 0;
};

struct WicTiffLanePlan final {
    const WicTiffLaneOpener* opener{nullptr};
    std::uint32_t lane_count{0U};
    std::uint32_t rows_per_lane{0U};
};

// 레인을 몇 개, 몇 줄씩 쓸지 정합니다. 레인 하나가 띠 하나를 맡으려면 띠가 스트립 경계와
// 맞아야 합니다 - 압축 스트립 하나가 사진 전체면 레인마다 처음부터 다시 풀어야 해서 오히려
// 느려지므로 그때는 레인을 쓰지 않습니다(`lane_count` 0). 회전을 적용하는 소스도 띠 하나에
// 사진 전체를 풀어야 하므로 같습니다.
[[nodiscard]] WicTiffLanePlan plan_tiff_lanes(
    const negaflow::core::TiffProbeInfo& info,
    const WicTiffDecodeControl& control,
    UINT output_height,
    bool scaled) noexcept;

// 레인마다 자기 띠를 동시에 풀고, 모인 덩이를 행 순서대로 sink 에 넘깁니다. 화소는 한 소스가
// 순서대로 푼 것과 같습니다 - 같은 디코더가 같은 행을 풀 뿐 나누는 자리만 다릅니다.
// sink 는 이미 begin 된 상태로 받고, 끝나면 이 함수가 complete 합니다.
[[nodiscard]] WicTiffDecodeStatus copy_tiff_rows_in_lanes(
    IWICBitmapSource* first_lane,
    const WicTiffLanePlan& plan,
    std::uint64_t stride_bytes,
    UINT width,
    UINT height,
    const WicTiffDecodeControl& control,
    WicTiffRowSink& row_sink,
    bool& sink_started,
    WicTiffDecodeResult& result);

}  // namespace negaflow::imageio::wic_tiff_detail
