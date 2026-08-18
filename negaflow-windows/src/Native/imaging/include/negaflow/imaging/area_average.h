#pragma once

// macOS `CIAreaAverage` 대응 — 사각형 안의 평균 RGBA.
//
// 살아 있는 호출부: macOS `FilmBaseEstimator.averageRGB`(스트립 폴백).
// Windows `strip_fallback_base` 는 격자+제외 마스크를 직접 평균하므로 이 함수를
// 쓰지 않습니다. 제품 원시연산과 `--develop-timing … areaavg` 가 여기를 부릅니다.
//
// ☠️ 부동소수 덧셈은 결합법칙이 없습니다. CPU 는 행 우선 왼쪽→오른쪽 `double` 누적,
//    GPU 는 `groupshared` 트리입니다. 평균의 허용 오차는 **1e-5** 입니다.

#include "negaflow/imaging/scanner_to_working.h"

#include <cstdint>

namespace negaflow::imaging {

struct AreaAverage final {
    double red{0.0};
    double green{0.0};
    double blue{0.0};
    double alpha{0.0};
    std::uint64_t count{0};
};

// `origin`+`extent` 가 이미지를 벗어나면 잘립니다. 빈 영역이면 false.
[[nodiscard]] bool area_average(
    const WorkingImage& image,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t extent_width,
    std::uint32_t extent_height,
    AreaAverage& average) noexcept;

[[nodiscard]] bool area_average(
    const negaflow::core::Rgba32F* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t stride_pixels,
    std::uint32_t origin_x,
    std::uint32_t origin_y,
    std::uint32_t extent_width,
    std::uint32_t extent_height,
    AreaAverage& average) noexcept;

}  // namespace negaflow::imaging
