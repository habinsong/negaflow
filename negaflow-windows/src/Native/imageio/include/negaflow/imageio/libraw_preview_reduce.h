#pragma once

#include "negaflow/imageio/decoded_image.h"

#include <cstdint>

namespace negaflow::imageio {

/// LibRaw 가 돌려준 16bit RGB 를 프리뷰 크기의 `rgba16` 으로 만듭니다.
///
/// LibRaw 는 축소 요청을 받지 못합니다 - 늘 원본 화소를 다 만들어 돌려줍니다. 그래서
/// 앞 판은 그것을 **원본 크기 그대로** 화소당 8바이트로 넓힌 뒤(68.3MP 스캐너 DNG 한 장에
/// 546MB) WIC 로 줄였습니다. 실측(2026-09-02, 이 기계):
///
/// | 원본 | 상자 | 넓히기 | 줄이기 | 합계 |
/// |---|---|---|---|---|
/// | 10056x6792 | 2560 | 185ms | 378ms | **563ms** |
/// | 10056x6792 | 3600 | 173ms | 412ms | **585ms** |
/// | 6959x4639  | 2560 |  86ms | 168ms | **254ms** |
///
/// 여기서는 두 가지를 바꿉니다.
/// ① **원본 크기로는 절대 넓히지 않습니다.** LibRaw 버퍼를 `48bppRGB` 그대로 WIC 에
///    넘기고, 화소당 8바이트로 넓히는 것은 줄어든 결과에만 합니다.
/// ② 요청 상자보다 **정수배** 이상 클 때는 먼저 그 정수배로 박스 평균을 냅니다. 정수배
///    평균은 코어마다 나눠 돌 수 있고, 그 뒤 WIC 가 볼 화소가 k^2 배 줄어듭니다.
///
/// 같은 실측에서 이 두 가지를 합치면 10056x6792 → 2560 이 **563ms → 83ms** 였습니다.
/// 마지막 보간은 지금과 같은 `WICBitmapInterpolationModeHighQualityCubic` 이고, 정수배
/// 박스 평균을 앞에 두는 것은 큰 축소비에서 알리아싱을 **줄입니다**.
///
/// `maximum_width` 나 `maximum_height` 가 0 이면 줄이지 않고 그대로 넓히기만 합니다.
struct LibRawPreviewReduceResult final {
    bool ok{false};
    /// 요청 상자에 맞추느라 실제로 줄였는지입니다.
    bool reduced{false};
    /// WIC 에 넘기기 전에 코어를 나눠 미리 평균 낸 정수배입니다(1 이면 안 했습니다).
    std::uint32_t box_average_factor{1U};
};

/// `source` 는 화소당 16bit 3채널이 촘촘히 놓인 `width * height * 3` 개 표본입니다.
[[nodiscard]] LibRawPreviewReduceResult reduce_libraw_rgb16_to_preview(
    const std::uint16_t* source,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t maximum_width,
    std::uint32_t maximum_height,
    std::uint64_t max_decoded_pixel_bytes,
    DecodedImage& destination) noexcept;

} // namespace negaflow::imageio
